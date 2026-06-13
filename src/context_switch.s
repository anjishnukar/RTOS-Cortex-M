.syntax unified
.cpu cortex-m3
.thumb

/* ARM Cortex-M special registers */
.equ NVIC_INT_CTRL,  0xE000ED04   /* Interrupt Control and State Register */
.equ NVIC_PENDSV_SET, 0x10000000  /* Bit to set PendSV pending */
.equ NVIC_SYSPRI14,  0xE000ED22   /* PendSV priority register */
.equ NVIC_PRIORITY_15, 0xFF       /* Lowest priority = 255 */

/* External symbols defined in kernel.c */
.extern current_task
.extern next_task

/*
 * os_start — launch the RTOS
 *
 * Called once from main() after all tasks are created.
 * Sets up SysTick, sets PendSV to lowest priority,
 * switches from MSP to PSP, and triggers the first context switch.
 */
.global os_start
.thumb_func
os_start:
    /* Set PendSV to lowest priority so it runs after all other ISRs */
    ldr r0, =NVIC_SYSPRI14
    mov r1, #NVIC_PRIORITY_15
    strb r1, [r0]

    /* Set PSP to 0 — signals to PendSV that this is the first switch */
    mov r0, #0
    msr psp, r0

    /* Configure SysTick for 1ms ticks at 12MHz (lm3s6965evb clock) */
    ldr r0, =0xE000E010         /* SysTick CTRL register */
    ldr r1, =0xE000E014         /* SysTick LOAD register */
    ldr r2, =0xE000E018         /* SysTick VAL register */

    ldr r3, =11999              /* (12,000,000 / 1000) - 1 = 11999 */
    str r3, [r1]                /* Set reload value */
    mov r3, #0
    str r3, [r2]                /* Clear current value */
    mov r3, #0x07               /* CLKSOURCE=1, TICKINT=1, ENABLE=1 */
    str r3, [r0]                /* Start SysTick */

    /* Trigger PendSV to do the first context switch */
    ldr r0, =NVIC_INT_CTRL
    ldr r1, =NVIC_PENDSV_SET
    str r1, [r0]

    /* Enable interrupts (they were disabled before os_start) */
    cpsie i

    /* Loop — control never returns here, PendSV takes over */
loop:
    b loop

/*
 * SysTick_Handler — fires every 1ms
 *
 * This is the scheduler's heartbeat. It calls the C scheduler function,
 * then pends PendSV to do the actual register save/restore.
 * We do the switch in PendSV (not here) because PendSV has lower priority,
 * ensuring the stack is clean when we switch.
 */
.global SysTick_Handler
.thumb_func
SysTick_Handler:
    /* Call the C scheduler to pick the next task */
    push {lr}                   /* save LR (EXC_RETURN value) */
    bl   os_schedule            /* C function in kernel.c */
    pop  {lr}

    /* Pend PendSV to do the actual context switch */
    ldr r0, =NVIC_INT_CTRL
    ldr r1, =NVIC_PENDSV_SET
    str r1, [r0]

    bx  lr                      /* return from SysTick ISR */

/*
 * PendSV_Handler — the actual context switch
 *
 * This is the most important function in the entire RTOS.
 * When this fires, the CPU has already pushed r0-r3, r12, lr, pc, xpsr
 * onto the PSP (process stack). We save r4-r11 manually, then swap stacks.
 *
 * Register usage inside this handler:
 *   r0  = scratch
 *   r1  = scratch
 *   r2  = pointer to current_task->stack_ptr
 *   r3  = pointer to next_task->stack_ptr
 */
.global PendSV_Handler
.thumb_func
PendSV_Handler:
    /* Disable interrupts during context switch — atomic operation */
    cpsid i

    /* Get current PSP value */
    mrs r0, psp

    /*
     * Is this the first ever context switch?
     * On first call, PSP is 0 (we set it in os_start).
     * If PSP is 0, skip saving current context — nothing to save yet.
     */
    cbz r0, load_new_context    /* if r0 == 0, branch to load */

    /*
     * SAVE current task context
     * At this point, the hardware has already pushed r0-r3,r12,lr,pc,xpsr
     * onto the PSP. We push r4-r11 manually.
     */
    stmdb r0!, {r4-r11}         /* push r4-r11, decrement-before, update r0 */

    /* Save updated PSP (= current task's stack pointer) back into TCB */
    ldr r2, =current_task       /* r2 = &current_task (pointer to the pointer) */
    ldr r2, [r2]                /* r2 = current_task (the TCB pointer) */
    str r0, [r2, #0]            /* current_task->stack_ptr = r0 (offset 0 = first field) */

load_new_context:
    /*
     * LOAD next task context
     * Get next_task->stack_ptr, pop r4-r11, update PSP.
     * CPU will pop r0-r3,r12,lr,pc,xpsr automatically on exception return.
     */
    ldr r3, =next_task
    ldr r3, [r3]                /* r3 = next_task */
    ldr r0, [r3, #0]            /* r0 = next_task->stack_ptr */

    ldmia r0!, {r4-r11}         /* pop r4-r11, increment-after, update r0 */

    /* Update PSP to point past the registers we just popped */
    msr psp, r0

    /* Update current_task = next_task */
    ldr r2, =current_task
    str r3, [r2]

    /* Re-enable interrupts */
    cpsie i

    /*
     * Return from exception using PSP.
     * 0xFFFFFFFD = return to Thread mode, use PSP, use floating-point saved state.
     * The CPU will automatically pop r0-r3,r12,lr,pc,xpsr from PSP,
     * effectively jumping to the new task's PC with its register state restored.
     */
    ldr lr, =0xFFFFFFFD
    bx  lr