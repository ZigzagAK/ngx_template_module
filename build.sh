#!/bin/bash

# Copyright, Aleksey Konovkin (alkon2000@mail.ru)
# BSD license type

if [ "$1" == "" ]; then
  echo "build.sh <clean/clean_all> <download/download_all> <build>"
  exit 0
fi

download=0
download_only=0
download_all=0
build_deps=0
clean_all=0
compile=0
build_only=0
make_clean=0

DIR="$(pwd)"

VERSION="1.18.0"
PCRE_VERSION="8.40"
ZLIB_VERSION="1.2.11"

SUFFIX=""

if [ "$BUILD_DIR" == "" ]; then
  BUILD_DIR="$DIR/build"
fi

if [ "$INSTALL_DIR" == "" ]; then
  INSTALL_DIR="$DIR/install"
fi

if [ "$ERR_LOG" == "" ]; then
  ERR_LOG=$DIR/build/error.log
fi

if [ "$BUILD_LOG" == "" ]; then
  BUILD_LOG=$DIR/build/build.log
fi

[ -e "$BUILD_DIR" ] || mkdir -p $BUILD_DIR

export ZLIB_PREFIX="$BUILD_DIR/deps/zlib"
export PCRE_PREFIX="$BUILD_DIR/deps/pcre"
export YAML_PREFIX="$BUILD_DIR/deps/yaml"

export LD_LIBRARY_PATH="-L$PCRE_PREFIX/lib:$ZLIB_PREFIX/lib:$YAML_PREFIX/lib"
export DYLD_LIBRARY_PATH=$LD_LIBRARY_PATH
export PATH=/usr/local/bin:/bin:/usr/bin:$PATH

ADDITIONAL_INCLUDES="-I$PCRE_PREFIX/include -I$ZLIB_PREFIX/include"
ADDITIONAL_LIBS="-L$PCRE_PREFIX/lib -L$ZLIB_PREFIX/lib"

function clean() {
  rm -rf install  2>>$ERR_LOG
  if [ $clean_all -eq 1 ]; then
    rm -rf $BUILD_DIR  2>>$ERR_LOG
  else
    rm -rf $(ls -1d $BUILD_DIR/* 2>>$ERR_LOG | grep -v deps)    2>>$ERR_LOG
  fi
  if [ $download_all -eq 1 ]; then
    rm -rf downloads 2>>$ERR_LOG
  fi
}

doclean=0
dobuild=0

for i in "$@"
do
  if [ "$i" == "download" ]; then
    download=1
  fi

  if [ "$i" == "download_all" ]; then
    download=1
    download_all=1
  fi

  if [ "$i" == "clean_all" ]; then
    clean_all=1
    doclean=1
  fi

  if [ "$i" == "build" ]; then
    dobuild=1
  fi

  if [ "$i" == "build_only" ]; then
    dobuild=1
    build_only=1
  fi

  if [ "$i" == "clean" ]; then
    doclean=1
  fi

  if [ "$i" == "compile" ]; then
    compile=1
  fi
done

if [ $doclean -eq 1 ]; then
  clean
fi

if [ $download -eq 1 ] && [ $dobuild -eq 0 ]; then
  download_only=1
fi

current_os=`uname`
if [ "$current_os" = "Linux" ]; then
  platform="linux"
  arch=`uname -p`
  shared="so"
  if [ -e /etc/redhat-release ]; then
    vendor='redhat'
    ver=`cat /etc/redhat-release | sed -e 's#[^0-9]##g' -e 's#7[0-2]#73#'`
    if [ $ver -lt 50 ]; then
      os_release='4.0'
    elif [ $ver -lt 60 ]; then
      os_release='5.0'
    elif [ $ver -lt 70 ]; then
      os_release='6.0'
    else
      os_release='7.0'
    fi
    if [ "$arch" != "x86_64" ]; then
      arch='i686'
    fi
    DISTR_NAME=$vendor-$platform-$os_release-$arch
  else
    vendor=$(uname -r)
    DISTR_NAME=$vendor-$platform-$arch
  fi
  OPENSSL_FLAGS="linux-x86_64"
fi
if [ "$current_os" = "Darwin" ]; then
  platform="macos"
  arch=`uname -m`
  vendor="apple"
  shared="dylib"
  OPENSSL_FLAGS="darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 no-ssl2 no-ssl3"
  CFLAGS="-arch x86_64"
  DISTR_NAME=$vendor-$platform-$arch
fi

case $platform in
  linux)
    # platform has been recognized
    ;;
  macos)
    # platform has been recognized
    ;;
  *)
    echo "I do not recognize the platform '$platform'." | tee -a $BUILD_LOG
    exit 1;;
esac

if [ -z "$BUILD_VERSION" ]; then
    BUILD_VERSION="develop"
fi

function build_pcre() {
  echo "Build PCRE" | tee -a $BUILD_LOG
  cd pcre-$PCRE_VERSION
  ./configure --prefix="$PCRE_PREFIX" --libdir="$PCRE_PREFIX/lib" >> $BUILD_LOG 2>>$ERR_LOG
  make -j 8 >> $BUILD_LOG 2>>$ERR_LOG
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  make install >> $BUILD_LOG 2>>$ERR_LOG
  cd ..
}

function build_zlib() {
  echo "Build ZLIB" | tee -a $BUILD_LOG
  cd zlib-$ZLIB_VERSION
  ./configure --prefix="$ZLIB_PREFIX" --libdir="$ZLIB_PREFIX/lib" >> $BUILD_LOG 2>>$ERR_LOG
  make -j 8 >> $BUILD_LOG 2>>$ERR_LOG
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  make install >> $BUILD_LOG 2>>$ERR_LOG
  cd ..
}

function build_yaml() {
  echo "Build YAML" | tee -a $BUILD_LOG
  cd libyaml
  ./bootstrap >> $BUILD_LOG 2>>$ERR_LOG
  ./configure --prefix="$YAML_PREFIX" --libdir="$YAML_PREFIX/lib" >> $BUILD_LOG 2>>$ERR_LOG
  make -j 8 >> $BUILD_LOG 2>>$ERR_LOG
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  make install >> $BUILD_LOG 2>>$ERR_LOG
  cd ..
}

function build_release() {
  cd nginx-$VERSION
  make clean >> $BUILD_LOG 2>>$ERR_LOG
  echo "Configuring release nginx-$VERSION" | tee -a $BUILD_LOG
  ./configure --prefix="$INSTALL_DIR/nginx-$VERSION$SUFFIX" \
              --with-http_auth_request_module \
              --with-cc-opt="-g -O0 $ADDITIONAL_INCLUDES -Wno-error=unused-value -Wno-error=unused-variable -Wno-error=unused-function -Wno-error=implicit-fallthrough" \
              --with-ld-opt="$ADDITIONAL_LIBS" \
              --with-stream \
              --add-module=../echo-nginx-module \
              --add-module=../ngx_dynamic_healthcheck \
              --add-module=../.. >> $BUILD_LOG 2>>$ERR_LOG

  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi

  echo "Build release nginx-$VERSION" | tee -a $BUILD_LOG
  make -j 8 >> $BUILD_LOG 2>>$ERR_LOG

  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  make install >> $BUILD_LOG 2>>$ERR_LOG
  cd ..
}

function gitclone() {
  LD_LIBRARY_PATH="" git clone $1 >> $BUILD_LOG 2> /tmp/err
  if [ $? -ne 0 ]; then
    cat /tmp/err
    exit 1
  fi
}

function gitcheckout() {
  git checkout $1 >> $BUILD_LOG 2> /tmp/err
  if [ $? -ne 0 ]; then
    cat /tmp/err
    exit 1
  fi
}

function download_module() {
  if [ $download -eq 1 ] || [ ! -e $3.tar.gz ]; then
    if [ $download_all -eq 1 ] || [ ! -e $3.tar.gz ]; then
      echo "Download $1/$2/$3.git from=$4" | tee -a $BUILD_LOG
      gitclone $1/$2/$3.git
      echo "$1/$2/$3.git" > $3.log
      echo >> $3.log
      cd $3
      gitcheckout $4
      echo $4" : "$(git log -1 --oneline | awk '{print $1}') >> ../$3.log
      echo >> ../$3.log
      git log -1 | grep -E "(^[Cc]ommit)|(^[Aa]uthor)|(^[Dd]ate)" >> ../$3.log
      cd ..
      tar zcf $3.tar.gz $3
      rm -rf $3
    else
      echo "Get $3" | tee -a $BUILD_LOG
    fi
  else
    echo "Get $3" | tee -a $BUILD_LOG
  fi
}

function download_dep() {
  if [ $download -eq 1 ] || [ ! -e $2-$3.tar.gz ]; then
    if [ $download_all -eq 1 ] || [ ! -e $2-$3.tar.gz ]; then
      echo "Download $2-$3.$4" | tee -a $BUILD_LOG
      LD_LIBRARY_PATH="" curl -s -L -o $2-$3.tar.gz $1/$2-$3.$4
      echo "$1/$2-$3.$4" > $2.log
    else
      echo "Get $2-$3.tar.gz" | tee -a $BUILD_LOG
    fi
  else
    echo "Get $2-$3.tar.gz" | tee -a $BUILD_LOG
  fi
}

function extract_downloads() {
  cd downloads

  for d in $(ls -1 *.tar.gz)
  do
    echo "Extracting $d" | tee -a $BUILD_LOG
    tar zxf $d -C $BUILD_DIR --keep-old-files 2>>$ERR_LOG
  done

  cd ..
}

function download() {
  mkdir -p $BUILD_DIR        2>>$ERR_LOG
  mkdir $BUILD_DIR/deps      2>>$ERR_LOG

  mkdir downloads             2>>$ERR_LOG
  mkdir downloads/lua_modules 2>>$ERR_LOG

  cd downloads

  download_dep http://nginx.org/download                                           nginx           $VERSION           tar.gz
  download_dep http://ftp.cs.stanford.edu/pub/exim/pcre                            pcre            $PCRE_VERSION      tar.gz
  download_dep http://zlib.net                                                     zlib            $ZLIB_VERSION      tar.gz


  download_module https://github.com      yaml        libyaml                          tags/0.2.2

  download_module https://github.com      openresty   echo-nginx-module                master
  download_module https://github.com      ZigzagAK    ngx_dynamic_healthcheck          1.3.3

  cd ..
}

function install_file() {
  echo "Install $1" | tee -a $BUILD_LOG
  if [ ! -e "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2" ]; then
    mkdir -p "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2"
  fi
  if [ "$4" == "" ]; then
    if [ "$3" == "" ]; then
      if [ -d "$1" ]; then
        cp -rL $1 "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2/"
      else
        cp -r $1 "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2/"
      fi
    else
      if [ -d "$1" ]; then
        cp -rL $1 "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2/$3"
      else
        cp -r $1 "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2/$3"
      fi
    fi
  else
    echo $4 > "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2/$3"
  fi
}

function install_gzip() {
  echo "Install $1" | tee -a $BUILD_LOG
  if [ ! -e "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2" ]; then
    mkdir -p "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2"
  fi
  if [ "$4" == "" ]; then
    if [ "$3" == "" ]; then
      tar zxf $1 -C "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2/"
    else
      tar zxf $1 -C "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2/$3"
    fi
  else
    echo $4 > "$INSTALL_DIR/nginx-$VERSION$SUFFIX/$2/$3"
  fi
}

function install_files() {
  for f in $(ls $1)
  do
    install_file $f $2
  done
}

function build() {
  cd $BUILD_DIR

  if [ $build_deps -eq 1 ] || [ ! -e deps/zlib ]; then
    build_zlib
  fi
  if [ $build_deps -eq 1 ] || [ ! -e deps/pcre ]; then
    build_pcre
  fi
  if [ $build_deps -eq 1 ] || [ ! -e deps/yaml ]; then
    build_yaml
  fi

  build_release

  install_files "$ZLIB_PREFIX/lib/libz.$shared*"             lib

  install_files "$PCRE_PREFIX/lib/libpcre.$shared*"          lib
  install_files "$PCRE_PREFIX/lib/libpcreposix.$shared*"     lib

  install_files "$YAML_PREFIX/lib/libyaml*.$shared*"         lib

  chmod 755 $(find $INSTALL_DIR/nginx-$VERSION$SUFFIX/lib -name "*.$shared*")

  cd $DIR
}

if [ $build_only -eq 0 ]; then
  clean
fi
download
if [ $download_only -eq 0 ]; then
  if [ $build_only -eq 0 ]; then
    extract_downloads
  fi
  build
fi

cd "$DIR"

exit

kernel_name=$(uname -s)
kernel_version=$(uname -r)

cd install

tar zcvf nginx-$VERSION$SUFFIX.tar.gz nginx-$VERSION$SUFFIX
rm -rf nginx-$VERSION$SUFFIX

cd ..

exit $r
