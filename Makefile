PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/opt/local/bin
CC = arm-apple-darwin-gcc
LD = arm-apple-darwin-ld

CFLAGS = -Wall -Werror -Wno-unused -std=c99
LDFLAGS = -lcrypto -lobjc -framework CoreFoundation -framework Foundation -framework UIKit -framework LayerKit -framework CoreGraphics -framework OfficeImport

all: MobilePushr package

MobilePushr: main.o MobilePushr.o FlickrCategory.o Flickr.o
	@echo -n "Linking $@... "
	@$(CC) $(LDFLAGS) -o $@ $^
	@echo "done."

%.o: %.m
	@echo -n "Compiling $<... "
	@$(CC) -c $(CFLAGS) $(CPPFLAGS) $< -o $@
	@echo "done."

package: MobilePushr
	@echo -n "Creating package... "
	@rm -fr Pushr.app
	@mkdir -p Pushr.app
	@cp MobilePushr Pushr.app/MobilePushr
	@cp Info.plist Pushr.app/Info.plist
	@cp icon.png Pushr.app/icon.png
	@cp Default.png Pushr.app/Default.png
	@echo "done."

clean:
	@echo -n "Cleaning... "
	@rm -fr *.o MobilePushr Pushr.app
	@echo "done."
