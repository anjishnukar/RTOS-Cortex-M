.syntax unified          /* Use unified ARM/Thumb syntax */
.cpu cortex-m3
.thumb                   /* All instructions are Thumb-2 */

/* Declare external symbols defined in the linker script */
.word _estack            /* Linker puts this at top of SRAM */

/* Vector table — must be at address 0x00000000 */
.section .vector_table, "a"
.word _estack            /* 0: Initial stack pointer */
.word Reset_Handler      /* 1: Reset */
.word Default_Handler    /* 2: NMI */
.word Default_Handler    /* 3: HardFault */
.word Default_Handler    /* 4: MemManage */
.word Default_Handler    /* 5: BusFault */
.word Default_Handler    /* 6: UsageFault */
.word 0                  /* 7-10: Reserved */
.word 0
.word 0
.word 0
.word Default_Handler    /* 11: SVCall */
.word Default_Handler    /* 12: Debug Monitor */
.word 0                  /* 13: Reserved */
.word Default_Handler    /* 14: PendSV  ← we'll use this for context switch */
.word SysTick_Handler    /* 15: SysTick ← our scheduler heartbeat */

/* Reset handler: runs first when CPU powers on or resets */
.section .text
.global Reset_Handler
.thumb_func
Reset_Handler:
    /* Step 1: Set stack pointer to top of SRAM */
    ldr r0, =_estack
    mov sp, r0

    /* Step 2: Copy .data section from flash to SRAM */
    ldr r0, =_sidata    /* source: where .data is stored in flash */
    ldr r1, =_sdata     /* destination: start of .data in SRAM */
    ldr r2, =_edata     /* end of .data in SRAM */
copy_data:
    cmp r1, r2
    bge zero_bss        /* if r1 >= r2, done copying */
    ldr r3, [r0], #4    /* load word from flash, post-increment */
    str r3, [r1], #4    /* store to SRAM, post-increment */
    b copy_data

    /* Step 3: Zero .bss section */
zero_bss:
    ldr r0, =_sbss
    ldr r1, =_ebss
    mov r2, #0
zero_loop:
    cmp r0, r1
    bge call_main
    str r2, [r0], #4
    b zero_loop

    /* Step 4: Jump to main() */
call_main:
    bl main
    /* If main returns (it shouldn't), loop forever */
hang:
    b hang

/* Default handler for unhandled interrupts — just loops */
.global Default_Handler
.thumb_func
Default_Handler:
    b Default_Handler

/* Weak aliases — these can be overridden in C files */
.weak SysTick_Handler
.thumb_set SysTick_Handler, Default_Handler

.weak PendSV_Handler
.thumb_set PendSV_Handler, Default_Handler