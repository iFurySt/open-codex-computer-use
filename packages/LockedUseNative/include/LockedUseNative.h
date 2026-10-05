#ifndef OCU_LOCKED_USE_NATIVE_H
#define OCU_LOCKED_USE_NATIVE_H
#include <stdint.h>

typedef struct {
    uint8_t audit_token[32];
    uint32_t effective_user_id;
    uint32_t audit_session_id;
    int32_t process_id;
} OCUPeerIdentity;

/* Kernel-supplied connection identity, including pid version in the token.
 * Never reconstruct it from a pid reported by a client. Returns 0 on success. */
int ocu_copy_peer_identity(int socket_fd, OCUPeerIdentity *out_identity);
/* 0: no allow ACE grants mutation; 1: unsafe; -1: inspection failed. */
int ocu_has_mutating_acl(int file_fd);
#endif
