#include "LockedUseNative.h"
#include <bsm/libbsm.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/acl.h>
#include <sys/stat.h>

_Static_assert(sizeof(audit_token_t) == 32, "Unexpected Darwin audit token ABI");

int ocu_copy_peer_identity(int socket_fd, OCUPeerIdentity *out) {
    if (!out) { errno = EINVAL; return -1; }
    memset(out, 0, sizeof(*out));
    audit_token_t token = {0};
    socklen_t size = sizeof(token);
    if (getsockopt(socket_fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) != 0) return -1;
    if (size != sizeof(token)) { errno = EINVAL; return -1; }
    memcpy(out->audit_token, &token, sizeof(token));
    out->effective_user_id = audit_token_to_euid(token);
    out->audit_user_id = audit_token_to_auid(token);
    out->audit_session_id = audit_token_to_asid(token);
    out->process_id = audit_token_to_pid(token);
    return 0;
}

int ocu_has_mutating_acl(int file_fd) {
    acl_t acl = acl_get_fd_np(file_fd, ACL_TYPE_EXTENDED);
    if (!acl) {
        /* Darwin returns ENOENT for an existing fd without an extended ACL. */
        if (errno == ENOENT) {
            struct stat info;
            if (fstat(file_fd, &info) == 0) return 0;
        }
        return -1;
    }
    if (acl_valid(acl) != 0) { acl_free(acl); return -1; }
    acl_entry_t entry;
    int entry_id = ACL_FIRST_ENTRY;
    int result = 0;
    unsigned int entries = 0;
    int entry_status;
    while ((entry_status = acl_get_entry(acl, entry_id, &entry)) == 0) {
        if (++entries > ACL_MAX_ENTRIES) { result = -1; break; }
        entry_id = ACL_NEXT_ENTRY;
        acl_tag_t tag;
        acl_permset_t permissions;
        if (acl_get_tag_type(entry, &tag) != 0 || acl_get_permset(entry, &permissions) != 0) {
            result = -1; break;
        }
        if (tag != ACL_EXTENDED_ALLOW) continue;
        const acl_perm_t mutations[] = {ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE,
            ACL_DELETE_CHILD, ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES,
            ACL_WRITE_SECURITY, ACL_CHANGE_OWNER};
        for (unsigned int index = 0; index < sizeof(mutations) / sizeof(mutations[0]); index++) {
            int granted = acl_get_perm_np(permissions, mutations[index]);
            if (granted < 0) { result = -1; break; }
            if (granted > 0) { result = 1; break; }
        }
        if (result != 0) break;
    }
    /* Darwin uses EINVAL to indicate that the final entry was exhausted. */
    if (result == 0 && entry_status < 0 && errno != EINVAL) result = -1;
    acl_free(acl);
    return result;
}

int ocu_has_any_acl(int file_fd) {
    acl_t acl = acl_get_fd_np(file_fd, ACL_TYPE_EXTENDED);
    if (!acl) return errno == ENOENT ? 0 : -1;
    acl_entry_t entry;
    int status = acl_get_entry(acl, ACL_FIRST_ENTRY, &entry);
    int result = status == 0 ? 1 : errno == EINVAL ? 0 : -1;
    acl_free(acl); return result;
}

int ocu_remove_extended_acl(int file_fd) {
    acl_t empty = acl_init(0);
    if (!empty) return -1;
    int result = acl_set_fd_np(file_fd, empty, ACL_TYPE_EXTENDED);
    acl_free(empty); return result;
}

int ocu_send_peer_socket(int channel_fd, int peer_fd) {
    unsigned char marker = 0x4f;
    struct iovec vector = { &marker, 1 };
    union { struct cmsghdr alignment; char bytes[CMSG_SPACE(sizeof(int))]; } control = {0};
    struct msghdr message = {0};
    message.msg_iov = &vector; message.msg_iovlen = 1;
    message.msg_control = control.bytes; message.msg_controllen = sizeof(control.bytes);
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET; header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(header), &peer_fd, sizeof(peer_fd));
    return sendmsg(channel_fd, &message, 0) == 1 ? 0 : -1;
}

int ocu_receive_peer_socket(int channel_fd) {
    unsigned char marker = 0;
    struct iovec vector = { &marker, 1 };
    union { struct cmsghdr alignment; char bytes[CMSG_SPACE(sizeof(int) * 8)]; } control = {0};
    struct msghdr message = {0};
    message.msg_iov = &vector; message.msg_iovlen = 1;
    message.msg_control = control.bytes; message.msg_controllen = sizeof(control.bytes);
    ssize_t count = recvmsg(channel_fd, &message, 0);
    if (count < 0) return -1;
    int received = -1, descriptors = 0, invalid = 0;
    for (struct cmsghdr *header = CMSG_FIRSTHDR(&message); header;
         header = CMSG_NXTHDR(&message, header)) {
        if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_RIGHTS ||
            header->cmsg_len < CMSG_LEN(0)) { invalid = 1; continue; }
        size_t length = header->cmsg_len - CMSG_LEN(0);
        if (length % sizeof(int)) invalid = 1;
        for (size_t offset = 0; offset + sizeof(int) <= length; offset += sizeof(int)) {
            int fd; memcpy(&fd, CMSG_DATA(header) + offset, sizeof(fd));
            if (++descriptors == 1) received = fd; else close(fd);
        }
    }
    if (count != 1 || marker != 0x4f || descriptors != 1 || invalid ||
        message.msg_flags & (MSG_CTRUNC | MSG_TRUNC) ||
        fcntl(received, F_SETFD, FD_CLOEXEC) != 0) {
        if (received >= 0) close(received);
        errno = EPROTO; return -1;
    }
    return received;
}
