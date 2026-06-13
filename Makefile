CC      = arm-none-eabi-gcc
AS      = arm-none-eabi-as
LD      = arm-none-eabi-ld
OBJCOPY = arm-none-eabi-objcopy
OBJDUMP = arm-none-eabi-objdump

CFLAGS  = -mcpu=cortex-m3 -mthumb -O0 -g3 -Wall \
          -ffreestanding -nostdlib -nostartfiles \
          -Iinclude

LDFLAGS = -T startup/linker.ld -nostdlib

SRCS    = src/main.c src/kernel.c src/tasks.c
ASM_SRCS = startup/startup.s src/context_switch.s
OBJS    = $(SRCS:.c=.o) $(ASM_SRCS:.s=.o)

TARGET  = rtos.elf

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	$(OBJDUMP) -d $@ > rtos.list   # disassembly for debugging

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $

%.o: %.s
	$(CC) $(CFLAGS) -c -o $@ $

qemu: $(TARGET)
	qemu-system-arm -machine lm3s6965evb -nographic \
	                -semihosting-config enable=on,target=native \
	                -kernel $(TARGET)

qemu-debug: $(TARGET)
	qemu-system-arm -machine lm3s6965evb -nographic \
	                -semihosting-config enable=on,target=native \
	                -kernel $(TARGET) -S -gdb tcp::1234

gdb:
	gdb-multiarch -ex "target remote localhost:1234" \
	              -ex "symbol-file $(TARGET)" $(TARGET)

clean:
	rm -f $(OBJS) $(TARGET) rtos.list

.PHONY: all qemu qemu-debug gdb clean