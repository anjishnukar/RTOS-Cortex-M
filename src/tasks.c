#include "rtos.h"

/* Semihosting output — QEMU captures this and prints to your terminal */
extern void os_print(const char *s);

static semaphore_t shared_sem;
static volatile uint32_t shared_counter = 0;

/*
 * Task A — increments shared counter 5 times, then delays
 */
void task_a(void) {
    while (1) {
        os_sem_wait(&shared_sem);   /* acquire mutex */
        for (int i = 0; i < 5; i++) {
            shared_counter++;
            os_yield();             /* let other tasks run mid-loop */
        }
        os_sem_post(&shared_sem);   /* release mutex */
        os_delay(100);              /* sleep 100ms */
    }
}

/*
 * Task B — decrements shared counter 3 times, then delays
 */
void task_b(void) {
    while (1) {
        os_sem_wait(&shared_sem);
        for (int i = 0; i < 3; i++) {
            shared_counter--;
            os_yield();
        }
        os_sem_post(&shared_sem);
        os_delay(150);
    }
}

/*
 * Task C — idle/observer task, runs when no one else wants the CPU
 */
void task_c(void) {
    uint32_t last_tick = 0;
    while (1) {
        uint32_t now = os_tick_count();
        if (now - last_tick >= 500) {
            /* Every 500ms, semihosting print to QEMU terminal */
            last_tick = now;
            /* In a real implementation you'd call printf here via semihosting */
        }
        os_yield();
    }
}

semaphore_t *get_shared_sem(void) { return &shared_sem; }