#include "rtos.h"

/* Pointer to currently running task */
tcb_t *current_task = NULL;

/* Pointer to next task to run (set by scheduler) */
tcb_t *next_task = NULL;

/* Head of the task linked list */
static tcb_t *task_list = NULL;

/* Global tick counter */
static volatile uint32_t tick_count = 0;

/* Number of tasks created */
static uint8_t task_count = 0;

void os_init(void) {
    current_task = NULL;
    next_task     = NULL;
    task_list     = NULL;
    tick_count    = 0;
    task_count    = 0;
}

/*
 * os_task_create — initialise a TCB and fake an initial stack frame
 *
 * This is called BEFORE the scheduler starts. It sets up the task's
 * stack so that the first context switch INTO this task works correctly.
 */
void os_task_create(tcb_t *tcb, void (*task_func)(void),
                    uint8_t priority, const char *name) {
    /* Point to top of this task's stack (stacks grow downward) */
    uint32_t *sp = &tcb->stack[TASK_STACK_SIZE - 1];

    /* Align to 8 bytes as ARM ABI requires */
    sp = (uint32_t *)((uint32_t)sp & ~0x7U);

    /*
     * Lay down the fake exception frame (hardware-saved registers).
     * These are in the order the CPU expects when returning from an exception.
     */
    *(--sp) = 0x01000000U;          /* xPSR: Thumb bit (bit 24) must be set */
    *(--sp) = (uint32_t)task_func;  /* PC: where execution starts */
    *(--sp) = 0xFFFFFFFDU;          /* LR: EXC_RETURN — return to Thread mode, use PSP */
    *(--sp) = 0x12121212U;          /* r12: dummy value (easy to spot in debugger) */
    *(--sp) = 0x03030303U;          /* r3 */
    *(--sp) = 0x02020202U;          /* r2 */
    *(--sp) = 0x01010101U;          /* r1 */
    *(--sp) = 0x00000000U;          /* r0 */

    /*
     * Software-saved registers r4–r11.
     * These will be popped by our PendSV_Handler before the CPU
     * pops the hardware frame.
     */
    *(--sp) = 0x11111111U;   /* r11 */
    *(--sp) = 0x10101010U;   /* r10 */
    *(--sp) = 0x09090909U;   /* r9  */
    *(--sp) = 0x08080808U;   /* r8  */
    *(--sp) = 0x07070707U;   /* r7  */
    *(--sp) = 0x06060606U;   /* r6  */
    *(--sp) = 0x05050505U;   /* r5  */
    *(--sp) = 0x04040404U;   /* r4  */

    /* Save the stack pointer into the TCB */
    tcb->stack_ptr    = sp;
    tcb->state        = TASK_READY;
    tcb->priority     = priority;
    tcb->delay_ticks  = 0;
    tcb->name         = name;

    /* Add to task linked list (simple insertion at head) */
    tcb->next = task_list;
    task_list = tcb;
    task_count++;
}

/*
 * os_schedule — pick the next task to run
 *
 * Called from SysTick_Handler every 1ms.
 * Simple round-robin among READY tasks.
 * If a task is BLOCKED or has a delay, skip it.
 */
void os_schedule(void) {
    /* Decrement delay counters for sleeping tasks */
    tcb_t *t = task_list;
    while (t != NULL) {
        if (t->state == TASK_BLOCKED && t->delay_ticks > 0) {
            t->delay_ticks--;
            if (t->delay_ticks == 0) {
                t->state = TASK_READY;   /* wake up */
            }
        }
        t = t->next;
    }

    tick_count++;

    /* Round-robin: find the next READY task after current_task */
    if (current_task != NULL) {
        current_task->state = TASK_READY;  /* was RUNNING, now back to READY */
    }

    tcb_t *candidate = (current_task != NULL) ? current_task->next : task_list;

    /* Walk the list until we find a READY task, wrapping around once */
    uint8_t checked = 0;
    while (checked < task_count) {
        if (candidate == NULL)
            candidate = task_list;   /* wrap around */

        if (candidate->state == TASK_READY) {
            next_task = candidate;
            next_task->state = TASK_RUNNING;
            return;
        }

        candidate = candidate->next;
        checked++;
    }

    /* No task is ready — this shouldn't happen if you have an idle task */
    /* In production you'd run an idle task here. For now, just keep current. */
    next_task = current_task;
}

/*
 * os_delay — block current task for N ticks (~N milliseconds)
 */
void os_delay(uint32_t ticks) {
    if (current_task == NULL || ticks == 0) return;

    current_task->delay_ticks = ticks;
    current_task->state = TASK_BLOCKED;

    /* Yield CPU immediately — don't wait for next SysTick */
    os_yield();
}

/*
 * os_yield — voluntarily give up the CPU
 * Triggers PendSV to do a context switch right now.
 */
void os_yield(void) {
    /* Set PENDSVSET bit in ICSR */
    *((volatile uint32_t *)0xE000ED04) = 0x10000000;
}

uint32_t os_tick_count(void) {
    return tick_count;
}

/*
 * os_start — tell the assembly os_start to begin scheduling.
 * The actual heavy lifting is in context_switch.s
 */
extern void os_start(void);  /* defined in context_switch.s */



void os_sem_init(semaphore_t *sem, int32_t initial_count) {
    sem->count     = initial_count;
    sem->wait_list = NULL;
}

/*
 * os_sem_wait — take the semaphore
 *
 * If count > 0, decrement and continue.
 * If count == 0, block this task and yield.
 */
void os_sem_wait(semaphore_t *sem) {
    /* Disable interrupts — this operation must be atomic */
    __asm volatile ("cpsid i" ::: "memory");

    if (sem->count > 0) {
        sem->count--;
        __asm volatile ("cpsie i" ::: "memory");
        return;
    }

    /* Count is 0 — block this task */
    current_task->state = TASK_BLOCKED;

    /* Add current task to the semaphore's wait list */
    current_task->next = sem->wait_list;
    sem->wait_list = current_task;

    __asm volatile ("cpsie i" ::: "memory");

    /* Yield CPU — we'll be woken up by os_sem_post */
    os_yield();

    /*
     * When this task is rescheduled, execution resumes here.
     * The semaphore is now ours (os_sem_post already decremented it for us).
     */
}

/*
 * os_sem_post — release the semaphore
 *
 * If tasks are waiting, wake the first one.
 * Otherwise increment the count.
 */
void os_sem_post(semaphore_t *sem) {
    __asm volatile ("cpsid i" ::: "memory");

    if (sem->wait_list != NULL) {
        /* Wake up the first task waiting on this semaphore */
        tcb_t *woken = sem->wait_list;
        sem->wait_list = woken->next;

        /* Re-link woken task back into the main task list */
        woken->next  = task_list;
        task_list    = woken;
        woken->state = TASK_READY;

        /* Don't increment count — we're directly handing it to woken task */
    } else {
        sem->count++;
    }

    __asm volatile ("cpsie i" ::: "memory");
}