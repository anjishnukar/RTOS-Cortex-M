#ifndef RTOS_H
#define RTOS_H

#include <stdint.h>
#include <stddef.h>

/* Maximum number of tasks the RTOS supports */
#define MAX_TASKS       8
#define TASK_STACK_SIZE 256   /* 256 words = 1KB per task stack */

/* Task states */
typedef enum {
    TASK_READY,
    TASK_RUNNING,
    TASK_BLOCKED,   /* waiting on a semaphore */
    TASK_SUSPENDED
} task_state_t;

/*
 * Task Control Block (TCB)
 * This is the heart of the RTOS. One TCB per task.
 * The first field MUST be stack_ptr — the context switch
 * assembly code relies on this being at offset 0.
 */
typedef struct tcb {
    uint32_t *stack_ptr;     /* MUST be first field (offset 0) */
    uint32_t stack[TASK_STACK_SIZE];
    task_state_t state;
    uint8_t priority;      /* lower number = higher priority */
    uint32_t delay_ticks;   /* for os_delay() */
    const char *name;          /* for debugging */
    struct tcb *next;          /* linked list pointer */
} tcb_t;

/*
 * Semaphore
 */
typedef struct {
    int32_t count;
    tcb_t *wait_list;    /* tasks blocked on this semaphore */
} semaphore_t;

/* Kernel API */
void os_init(void);
void os_task_create(tcb_t *tcb, void (*task_func)(void),
                        uint8_t priority, const char *name);
void os_start(void);
void os_yield(void);
void os_delay(uint32_t ticks);
uint32_t os_tick_count(void);

/* Semaphore API */
void os_sem_init(semaphore_t *sem, int32_t initial_count);
void os_sem_wait(semaphore_t *sem);
void os_sem_post(semaphore_t *sem);

/* Called by SysTick ISR (defined in startup.s) */
void SysTick_Handler(void);
void PendSV_Handler(void);

#endif