#!/bin/bash
PREFIX="$(pwd)/Build";
MAKE_LOGS="${PREFIX}/log";
CROSS_DEVELOPER="$(xcode-select -print-path)";
ARCHS="x86_64 arm64"

PS3="please select iOS version > "
select item in $(xcodebuild -showsdks | grep iphoneos | awk '{print $NF}' | sed -e "s@iphoneos@@g")
do
    if [ "${REPLY}" = "q" ]; then
        echo "Exit from system."
        exit 
    fi
    if [ -z "$item" ] ; then
        continue
    fi
    case "$item" in
        quit ) echo "Exit from system."
           break ;;
        * ) echo "you select $item ($REPLY)"
           break ;;
    esac
done

SDKVER=${item};
MIN_SUPPORT_VERSION="11.0"
NETSNMPLIBS="";

# prepare openssl lib
mkdir openssl-for-iphone
if [[ ! -d ../openssl-for-iphone/dist/ ]]; then
  echo "Openssl libraries are required (libcrypto.a libssl.a and headers)"
  exit 1
fi
cp -r ../openssl-for-iphone/dist/* ./openssl-for-iphone/
OPENSSLDIR="$(pwd)/openssl-for-iphone";

for arch in ${ARCHS}; do
    if [[ "${arch}" == "x86_64" ]]; then
        export CROSS_TYPE=Simulator
    else
        export CROSS_TYPE=OS
    fi

    CROSS_TOP="${CROSS_DEVELOPER}/Platforms/iPhone${CROSS_TYPE}.platform/Developer";
    CROSS_CHAIN="${CROSS_TOP}/usr/bin";
    CROSS_SDK="iPhone${CROSS_TYPE}${SDKVER}.sdk";
    CROSS_ARCH="${CROSS_SDK}-${arch}";
    SDK_DIR="${CROSS_TOP}/SDKs/${CROSS_SDK}";
    TOOL_DIR="${CROSS_DEVELOPER}/Toolchains/XcodeDefault.xctoolchain";

    cc=${CROSS_DEVELOPER}/usr/bin/gcc;
    ld=${CROSS_DEVELOPER}/usr/bin/ld;
    ar=${TOOL_DIR}/usr/bin/ar;
    build=$(${cc} -v 2>&1 | grep "Target" | awk '{print $2}');
    host=$(${cc} -arch ${arch} -v 2>&1 | grep "Target" | awk '{print $2}');
    target=${host};

    CFLAGS="-arch ${arch}";
    CFLAGS="${CFLAGS} -pipe";
    CFLAGS="${CFLAGS} -no-cpp-precomp";
    CFLAGS="${CFLAGS} -mios-version-min=${MIN_SUPPORT_VERSION}";
    CFLAGS="${CFLAGS} -I${SDK_DIR}/usr/include";

    LDFLAGS="-L${SDK_DIR}/usr/lib";
    # LDFLAGS="${LDFLAGS} -L${SDK_DIR}/usr/lib/system";
    # LDFLAGS="${LDFLAGS} -L${SDK_DIR}/usr/lib/system/host";
    LDFLAGS="${LDFLAGS} -F${SDK_DIR}/System/Library/Frameworks";
    # LDFLAGS="${LDFLAGS} -F${SDK_DIR}/System/Library/Frameworks/CoreServices";

    export CFLAGS="${CFLAGS}";
    export LDFLAGS="${LDFLAGS}";
    echo "build=${build}"
    echo "host=${host}"
    CONFIGOPTIONS="";
    CONFIGOPTIONS="${CONFIGOPTIONS} --prefix=${PREFIX}/${CROSS_ARCH}";
#    CONFIGOPTIONS="${CONFIGOPTIONS} --exec-prefix=${PREFIX}/${CROSS_ARCH}";
#    CONFIGOPTIONS="${CONFIGOPTIONS} --includedir=${PREFIX}/${CROSS_ARCH}/include";
    # CONFIGOPTIONS="${CONFIGOPTIONS} --build=${build}";
    CONFIGOPTIONS="${CONFIGOPTIONS} --host=${host}";
    # CONFIGOPTIONS="${CONFIGOPTIONS} --target=${target}";
#    CONFIGOPTIONS="${CONFIGOPTIONS} --with-install-prefix=/tmp/
    CONFIGOPTIONS="${CONFIGOPTIONS} --with-sysroot=${SDK_DIR}";
    CONFIGOPTIONS="${CONFIGOPTIONS} --with-defaults";
    CONFIGOPTIONS="${CONFIGOPTIONS} --with-cc=${cc}";
    CONFIGOPTIONS="${CONFIGOPTIONS} --with-linkcc=${cc}";
    CONFIGOPTIONS="${CONFIGOPTIONS} --with-ar=${ar}";
    CONFIGOPTIONS="${CONFIGOPTIONS} --with-gnu-ld";
    CONFIGOPTIONS="${CONFIGOPTIONS} --with-openssl=${OPENSSLDIR}";
#    CONFIGOPTIONS="${CONFIGOPTIONS} --with-cflags=\"${CFLAGS}\"";
#    CONFIGOPTIONS="${CONFIGOPTIONS} --with-ldflags=${LDFLAGS}";
    CONFIGOPTIONS="${CONFIGOPTIONS} --enable-reentrant";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-embedded-perl";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-perl-cc-checks";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-shared";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-agent";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-applications";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-manuals";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-scripts";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-mibs";
    CONFIGOPTIONS="${CONFIGOPTIONS} --disable-snmptrapd-subagent";

    MAKE_LOGS="${PREFIX}/${CROSS_ARCH}/log";
    mkdir -p ${MAKE_LOGS};
    echo "./configure ${CONFIGOPTIONS}"
    ./configure ${CONFIGOPTIONS} 2>&1 | tee ${MAKE_LOGS}/configure.log
    if [[ 0 != ${PIPESTATUS[0]} ]]; then
        echo "configure error ${CROSS_ARCH}";
        exit 1;
    fi

    make 2>&1 | tee ${MAKE_LOGS}/build.log
    if [[ 0 != ${PIPESTATUS[0]} ]]; then
        echo "make error ${CROSS_ARCH}";
        exit 1;
    fi

    make install 2>&1 | tee ${MAKE_LOGS}/install.log
    if [[ 0 != ${PIPESTATUS[0]} ]]; then
        echo "install error ${CROSS_ARCH}";
        exit 1;
    fi

    make clean 2>&1 | tee ${MAKE_LOGS}/clean.log
    if [[ 0 != ${PIPESTATUS[0]} ]]; then
        echo "clean error ${CROSS_ARCH}";
        exit 1;
    fi

    NETSNMPLIB="${PREFIX}/${CROSS_ARCH}/lib/libnetsnmp.a";

    if [[ "" == ${NETSNMPLIBS} ]]; then
        DELEGATE_ARCHDIR="${PREFIX}/${CROSS_ARCH}";
        NETSNMPLIBS="${NETSNMPLIB}";
    else
        NETSNMPLIBS="${NETSNMPLIBS} ${NETSNMPLIB}";
    fi
done

INSTALLDIR="${PREFIX}/net-snmp-for-iphone";
mkdir -p "${INSTALLDIR}/lib";
lipo -create ${NETSNMPLIBS} -output "${INSTALLDIR}/lib/libnetsnmp.a";

mkdir -p "${INSTALLDIR}/include";
cp -R ${DELEGATE_ARCHDIR}/include/net-snmp ${INSTALLDIR}/include/;
rm -rf ${OPENSSLDIR}
echo; echo "Done."; echo;
