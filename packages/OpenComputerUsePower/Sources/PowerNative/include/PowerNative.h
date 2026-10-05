#pragma once
#include <stdint.h>
// Returned strings are malloc-owned; caller frees with ocu_power_free.
typedef char *(*ocu_power_handler)(const char *request, uint32_t uid, int32_t pid, const char *connection_id);
char *ocu_power_helper_request(const char *json);
int ocu_power_helper_listen(ocu_power_handler handler);
void ocu_power_free(char *value);
int ocu_power_peer_uid(int fd, uint32_t *uid);
int ocu_power_secure_root_file(const char *path);

int ocu_power_secure_root_directory(const char *path);

int ocu_power_no_extended_acl(const char *path);

int ocu_power_is_signed_host(void);

// Read-only, fixed PSTR sensor. No arbitrary SMC commands or writes.
int ocu_power_system_watts(double *watts);
