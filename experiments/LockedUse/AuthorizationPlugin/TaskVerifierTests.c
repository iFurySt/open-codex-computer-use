#include <assert.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
extern int32_t ocu_verify_broker_task(const void *, const char *);
#ifndef OCU_SIGNING_TEAM
#error "Signing team required"
#endif
int main(int argc, char **argv) {
    assert(argc == 2);
    audit_token_t token = {0};
    mach_msg_type_number_t count = TASK_AUDIT_TOKEN_COUNT;
    assert(task_info(mach_task_self(), TASK_AUDIT_TOKEN, (task_info_t)&token, &count) == KERN_SUCCESS);
    int32_t result = ocu_verify_broker_task(&token, OCU_SIGNING_TEAM);
    if (result == -1) { puts("Kernel task verifier unavailable; legacy verification remains required."); return 0; }
    assert(result == (strcmp(argv[1], "match") == 0 ? 1 : 0));
    assert(ocu_verify_broker_task(&token, "AAAAAAAAAA") == 0);
    assert(ocu_verify_broker_task(&token, "malformed") == -2);
    assert(ocu_verify_broker_task(NULL, OCU_SIGNING_TEAM) == -2);

    puts("Kernel task verifier: live signature/category/runtime identity checked; wrong team and malformed input rejected.");
    return 0;
}
