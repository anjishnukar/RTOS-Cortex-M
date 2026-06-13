#include "rtos.h"

/* Task stacks and TCBs — statically allocated */
static tcb_t tcb_a, tcb_b, tcb_c;

extern void task_a(void);
extern void task_b(void);
extern void task_c(void);
extern semaphore_t *get_shared_sem(void);

int main(void) {
    /* 1. Initialise kernel */
    os_init();

    /* 2. Create tasks */
    os_task_create(&tcb_a, task_a, 1, "task_a");
    os_task_create(&tcb_b, task_b, 2, "task_b");
    os_task_create(&tcb_c, task_c, 3, "task_c");  /* lowest priority */

    /* 3. Initialise semaphore as a binary mutex (initial count = 1) */
    os_sem_init(get_shared_sem(), 1);

    /* 4. Start the RTOS — this never returns */
    os_start();

    return 0;  /* never reached */
}