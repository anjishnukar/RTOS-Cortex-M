/* Memory regions for LM3S6965 (QEMU target) */
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 256K
    SRAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

/* Stack size — 4KB for the main/kernel stack */
_stack_size = 0x1000;

SECTIONS
{
    /* Vector table and code go into flash */
    .text :
    {
        KEEP(*(.vector_table))   /* Vector table must be first */
        *(.text*)                /* All code */
        *(.rodata*)              /* Read-only data (string literals etc.) */
        _etext = .;              /* End of flash content */
    } > FLASH

    /* Initialized data: lives in flash, copied to SRAM at startup */
    .data :
    {
        _sdata = .;              /* Start of data in SRAM */
        *(.data*)
        _edata = .;              /* End of data in SRAM */
    } > SRAM AT > FLASH          /* AT > FLASH means stored in flash */

    _sidata = LOADADDR(.data);   /* Where .data is stored in flash */

    /* Zero-initialized data: only needs a size, not flash storage */
    .bss :
    {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > SRAM

    /* Stack at top of SRAM */
    .stack (NOLOAD) :
    {
        . = ALIGN(8);
        _sstack = .;
        . = . + _stack_size;
        _estack = .;             /* Stack grows DOWN from here */
    } > SRAM
}