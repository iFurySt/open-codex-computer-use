#ifndef OCU_LOCKED_USE_NATIVE_H
#define OCU_LOCKED_USE_NATIVE_H
#include <stdint.h>

typedef struct {
    uint8_t audit_token[32];
    uint32_t effective_user_id;
    uint32_t audit_user_id;
    uint32_t audit_session_id;
    int32_t process_id;
} OCUPeerIdentity;

/* Kernel-supplied connection identity, including pid version in the token.
 * Never reconstruct it from a pid reported by a client. Returns 0 on success. */
int ocu_copy_peer_identity(int socket_fd, OCUPeerIdentity *out_identity);
/* 0: no allow ACE grants mutation; 1: unsafe; -1: inspection failed. */
int ocu_has_mutating_acl(int file_fd);
int ocu_has_any_acl(int file_fd);
int ocu_remove_extended_acl(int file_fd);
/* SCM_RIGHTS transfers a connected endpoint for kernel peer verification only. */
int ocu_send_peer_socket(int channel_fd, int peer_fd);
int ocu_receive_peer_socket(int channel_fd);
#endif
