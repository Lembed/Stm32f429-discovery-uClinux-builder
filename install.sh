
#!/bin/bash

# install tools and genromfs
sudo apt-get install genromfs wget git

sudo git clone https://github.com/ntfreak/openocd.git openocd
cd openocd; ./bootstrap
./configure --prefix=/usr/local --enable-stlink
echo -e "all:\ninstall:" > doc/Makefile
make
sudo make install

wget https://sourcery.mentor.com/public/gnu_toolchain/arm-uclinuxeabi/arm-2010q1-189-arm-uclinuxeabi-i686-pc-linux-gnu.tar.bz2
tar jxvf arm-2010q1-189-arm-uclinuxeabi-i686-pc-linux-gnu.tar.bz2
export PATH=`pwd`/arm-2010q1/bin:$PATH


