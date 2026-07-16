KDIR ?= /lib/modules/$(shell uname -r)/build

obj-m += i2c-hid.o
obj-m += i2c-hid-acpi.o
i2c-hid-y := i2c-hid-core.o i2c-hid-dmi-quirks.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
