#!/bin/bash

###############  D O C U M E N T A T I O N   F O R   U S E R S  ###############
#
# * This script will happily run with without any arguments or environment
#   variables and generate an unsigned xcode archive. However, if you provide
#   the following, extra things will happen:
#
#   - If BUILD_CONFIGURATION is defined, its value is passed to xcode; known
#     valid values are "Debug" and "Release". If undefined, we force "Debug"
#     (xcodebuild's default is "Release" - and they *are* case sensitive).
#
#   - If ADHOC_ENTITLEMENTS_PATH is the path to an entitlements plist and
#     ADHOC_IPA_PROFILE_NAME is the name string from a mobile provisioning
#     profile and ADHOC_SIGNING_ID is the numeric key value from the
#     keychain, then an ad-hoc ipa will be exported.
#
#   - If ENTER_ENTITLEMENTS_PATH is the path to an entitlements plist and
#     ENTER_IPA_PROFILE_NAME is the name string of a mobile provisioning
#     profile and ENTER_SIGNING_ID is the numeric key value from the
#     keychain, then an enterprise ipa will be exported.
#
#   - If STORE_ENTITLEMENTS_PATH is the path to an entitlements plist and
#     STORE_SIGNING_ID is the numeric key value from the keychain, then an
#     xcode archive suitable for upload to Apple will be produced.
#

#########  D O C U M E N T A T I O N   F O R   M A I N T A I N E R S  #########
#
# * This script is based on iosBuild.sh and SilentTextBuild.sh circa 2015-07-06
#   combining the former's log verbosity and intermediate product preservation
#   with the latter's configurability and default xcarchive cleanliness.
#
# * This aborts without finishing if it fails to build a git submodule or the
#   unsigned archive, since finishing is more dangerous than helpful in that
#   scenario. Otherwise, it counts errors and returns 0 if none else 1.
#
# * This variant maintains all its ancestors' conventions with respect to log
#   output format, so iosPublishLogs.sh can reformat its log into html.
#
# * In an pinch, add --no-strict to codesign --verify steps by setting in the
#   environment  CODESIGN_VERIFY=NOSTRICT .
#
# * To track down mismatched ' " } etc., temporarily replace "^#:#" with "    ".


####################  U T I L I T Y   F U N C T I O N S  ######################

# Utility function to print boxed text. Argument(s) can contain embedded "\n".
# Note the script that translates this log into html recognizes these boxes, as
# well as lines beginning with "! ", "? " and "+ " (bash -x output).
# Note we'd emit markdown syntax but it wants to make documents, not log files.
#:# echo 'Defining function echo_in_box()'
function echo_in_box()
{
  local IFS=''
  printf "\n"
  printf "$*\n" | \
    awk '{t[++x]=" "$0" "; if ((l=length(t[x]))>w){w=l}} END{for (i=1;i<=w;++i){s=s"-"}; print "."s"."; for(i=1;i<=x;++i){printf "!%-*s!\n",w,t[i]}; print "'\''"s"'\''"}'
  printf "\n"
}

# Utility function to abort the script, printing a message.
# When composing error messages passed to this function, keep in mind that:
# 1) This leaves errorCount.txt containing "Build Aborted".
# 2) The index generated by iosPublishLogs shows this message as a tooltip.
#:# echo 'Defining function failed()'
function failed()
{
  local error=${1:-Undefined error}
  echo "? Failed: $error" >&2
  exit 1
}


function handle_xcodebuild_result()
{
  local errcode="$1"
  local project="$2"
  local logfile="$3"
  local errfail="$4"
  if [ $errcode -ne 0 ]
  then
    ((errorCount++))
    echo "? xcodebuild $project failed, code $errcode" >&2
    echo "! Log file: logfile"
    if [ $(fgrep -c ': fatal error: ' $logfile) -gt 0 ]
    then
      echo '! Last log line containing the string ": fatal error: ":'
      fgrep ': fatal error: ' $logfile | tail -n1 | sed 's/^/    /'
    fi
    echo '! Last 20 log lines:'
    tail -n20 $logfile | sed 's/^/    /'
    if [ "$errfail" == 'ERROR_IS_FATAL' ]
    then
      failed "xcodebuild $project gave error $errcode."
    fi
  else
    echo "xcodebuild $project succeeded; last 3 lines of ${logfile}:"
    tail -n3 $logfile | sed 's/^/    /'
  fi
}


function handle_codesign_result()
{
  local errcode="$1"
  local action="$2"
  if [ $errcode -ne 0 ]
  then
    ((errorCount++))
    echo "? $action failed, code $errcode" >&2
  else
    echo "$action succeeded"
  fi
}


#:# echo 'Defining function get_architecture_only()'
function get_architecture_only()
{
  local got=$1
  local archs_only=`expr "$got" : '.*:\(.*\)'`
        archs_only="${archs_only%"${archs_only##*[![:space:]]}"}"
        archs_only="${archs_only#"${archs_only%%[![:space:]]*}"}"
  echo  $archs_only
}


#:# echo 'Defining function get_architecture_from_binary() '
function get_architecture_from_binary() 
{
  local binary=$1
  local archive_archs=`xcrun -sdk iphoneos lipo -info "$binary"`
  local archs=$(get_architecture_only "$archive_archs")
  echo  $archs
}


#:# echo 'Defining function test_architecture_wanted_vs_got()'
function test_architecture_wanted_vs_got()
{
  local entity=$1
  local wanted=$2
  local got=$3
  local handling=$4

  if [ "$wanted" != "$got" ]
  then
    if [ "$handling" == 'ABORT' ]
    then
      failed "$entity wants architectures $2 got $3."
    fi
    echo "? $entity wants architectures $2 got $3; continuing"
  fi
}


#################  G L O B A L   I N I T I A L I Z A T I O N  #################


# The following counts errors that make the script's output useless, but are
# not severe enough to abort its execution entirely.  Finishing execution
# sometimes provides clues to the reason for an otherwise obscure error.
errorCount=0

# iosPublishLogs.sh puts errorCount.txt content into a link title; normally that
# will be Errors:N but in case execution aborts before we have an accurate error
# count, set a default here:
echo 'Build Aborted' >| errorCount.txt



# A way to force an absolute path
BUILD_BASE=`pwd`

# Where to find oddball tools that are supplied by the build environment:
TOOL_BASE=`dirname "$BUILD_BASE"`

# Tool to adjust contents of Plists.
PlistBuddy=/usr/libexec/PlistBuddy

# Tool to list provisioning profiles
PROV_PROF_TOOL=$TOOL_BASE/provprof.awk

# Tool to display provisioning profile content
PROV_PROF_CONTENT_TOOL=$TOOL_BASE/provprofcontent.awk



echo_in_box 'Describing this script and its tools:'
(ls -FTl "$BASH_SOURCE"; ls -FTlL "$BASH_SOURCE") | sort -ru
echo
(ls -FTl "$PlistBuddy"; ls -FTlL "$PlistBuddy") | sort -ru
echo


echo_in_box 'Checking and describing build configuration and options:'
# Forbid parameters, to catch obsolete invocations
if (( $# != 0 )); then
  failed "This script does not allow any parameters; $argcount given."
fi
echo '! Showing BUILD_CONFIGURATION:'
echo "    ${BUILD_CONFIGURATION=Debug}"
echo '! Showing BUILD_VERSION_PREFIX and BUILD_NUMBER:'
echo "    '${BUILD_VERSION_PREFIX=}'  '$BUILD_NUMBER'"
echo '! Showing BUILD_OPTIONS:'
echo "    ${BUILD_OPTIONS=}"
echo '! Showing ADHOC_ENTITLEMENTS_PATH:'
echo "    $ADHOC_ENTITLEMENTS_PATH"
echo '! Showing ENTER_ENTITLEMENTS_PATH:'
echo "    $ENTER_ENTITLEMENTS_PATH"
echo '! Showing STORE_ENTITLEMENTS_PATH:'
echo "    $STORE_ENTITLEMENTS_PATH"
echo


# Other symbols shared across mainline functions shall use all-caps * names;
# fix flaws as found.
# BUILD_*_NAME are a single token with no "/" or ".ext" .
# BIULD_*_PATH are absolute paths.

BUILD_APP_ARCHS="armv7 arm64"

BUILD_ARCHIVE_NAME="SilentPhone"        # our choice
BUILD_ARCHIVE_PATH="$BUILD_BASE/$BUILD_ARCHIVE_NAME.xcarchive"

PROJECT_NAME=VoipPhone
PROJECT_NAME_ENT=EnterprisePhone

BUILD_ADHOC_IPA="$BUILD_BASE/$PROJECT_NAME.ipa"
BUILD_ENTER_IPA="$BUILD_BASE/$PROJECT_NAME_ENT.ipa"

BUILD_APP_VOIPPHONE_DIR="apple/ios"
PROJECT_WORKSPACE="$PROJECT_NAME.xcodeproj/project.xcworkspace"

BUILD_KITS="$BUILD_BASE/kits"
BUILD_KIT_BASE="$BUILD_KITS/base"
BUILD_KIT_ADHOC="$BUILD_KITS/adhoc"
BUILD_KIT_ENTER="$BUILD_KITS/enter"
BUILD_KIT_STORE="$BUILD_KITS/store"

# This script cannot choose the application name; it is set by (and should
# probably be read from) xcodebuild settings: PRODUCT_NAME which in turn was
# set from TARGET_NAME.
BUILD_APP_NAME="VoipPhone"

# Centralize product peculiarity configuration
ENTER_IPA_BUNDLE_ID=com.silentcircle.enterprisephone
ENTER_IPA_BUNDLE_DISPLAY_NAME="Enterprise Phone"
STORE_ARCHIVE_PATH="$BUILD_KIT_STORE/store.xcarchive"

# Finally, determine and state what we're about to do:
echo_in_box 'Determining Build Plan:'
echo "This build intends to produce:"
echo "   - an unsigned Xcode archive"

if [ -n "$ADHOC_ENTITLEMENTS_PATH" ] \
&& [ -n "$ADHOC_IPA_PROFILE_NAME"  ] \
&& [ -n "$ADHOC_SIGNING_ID" ]
then
  echo "   - a signed ad-hoc ipa"
  MAKING_ADHOC_IPA=Yes
fi

if [ -n "$ENTER_ENTITLEMENTS_PATH" ] \
&& [ -n "$ENTER_IPA_PROFILE_NAME"  ] \
&& [ -n "$ENTER_SIGNING_ID" ]
then
  echo "   - a signed enterprise ipa"
  MAKING_ENTERPRISE_IPA=Yes
fi

if [ -n "$STORE_ENTITLEMENTS_PATH" ] \
&& [ -n "$STORE_SIGNING_ID" ]
then
  echo "   - a signed Xcode archive"
  MAKING_STORE_ARCHIVE=Yes
fi



###################  M A I N L I N E   F U N C T I O N S   ####################

# This script assumes that is being run for the top of the tree
# Verify by checking for the .git directory
#
#:# echo 'Defining function validate_build_root()'
function validate_build_root()
{
  echo "! BUILD_BASE is '$BUILD_BASE'"
  if [ ! -e .git ]
  then
    failed "Incorrect default directory; build in directory containing .git ."
  fi
}


#:# echo "Defining function describe_keychain()"
function describe_keychain()
{
  echo '! Listing active keychains:'
  security list-keychains

  echo
  echo '! Listing all codeSigning identities on keychain:'
  security find-identity -p codesigning -v
}


#:# echo 'Defining function describe_environment()'
function describe_environment()
{
  echo "! Showing who I am:"
  whoami
  echo 
  echo "! Showing operating system:"
  (sw_vers; sysctl -n kern.boottime; date +}%Z) | \
    awk -F '[\t}]' 'NR==3{$0="\tbooted"} {a=a $2 " "} END{print a}'

  echo
  echo "! Showing available disk space:"
  df -m .
  echo
  echo "! Showing Xcode version:"
  xcodebuild -version
  echo 
  # NOTE: the following string is relied upon by iosPublishLogs.sh:
  echo "! Showing latest repository change:"
  git log --format="%h %an %cd %s" -1
}


#:# echo 'Defining function describe_sdks()'
function describe_sdks()
{
  echo "! Listing available SDKs:"
  xcodebuild -showsdks  
}


#:# echo 'Defining function describe_schemes()'
function describe_schemes()
{
  echo "! Listing available Schemes:"
  find . -name $PROJECT_NAME.xcodeproj
}


#:# echo "Defining function describe_xcode_workspace()"
function describe_xcode_workspace()
{
  xcodebuild -list -workspace "$BUILD_APP_VOIPPHONE_DIR/$PROJECT_WORKSPACE"
}


#:# echo 'Defining function build_prepare()'
function build_prepare()
{
  echo '! Creating "libs" subdirectory:'
  mkdir -v $BUILD_BASE/libs
  echo '! Creating "kits" subdirectory:'
  mkdir -v $BUILD_BASE/kits
}


#:# echo 'Defining function polarssl_build()'
function polarssl_build()
{
  local project_name="polarssl"
  local project="$project_name"".xcodeproj"
  local directory="support/polarssl/"
  local logfile="$BUILD_BASE""/xcodebuild_""$project_name"".log"

  pushd $directory  > /dev/null

  echo "! Describing ${project_name}:"
  xcodebuild -list -project $project
  echo

  echo "! Building ${project_name}:"
  set -x
  xcodebuild -verbose                                        \
             -project $project                               \
             -sdk iphoneos                                   \
             -configuration $BUILD_CONFIGURATION clean build \
             $BUILD_OPTIONS                                  \
             ARCHS="$BUILD_APP_ARCHS"                        \
  >| $logfile

  local status=$?
  set +x
  handle_xcodebuild_result $status "$project_name" "$logfile" ERROR_IS_FATAL

  popd > /dev/null
}


#:# echo 'Defining function polarssl_post()'
function polarssl_post()
{
  local source="$BUILD_BASE/support/polarssl/build/$BUILD_CONFIGURATION-iphoneos/libpolar_ssl.a"
  echo "! Copying libspolarssl.a to libs/:"
  cp "$source" $BUILD_BASE/libs/ || failed "Cannot install libspolarssl.a ."
}


#:# echo 'Defining function polarssl_verify()'
function polarssl_verify()
{
  echo "! Verifying libspolarssl.a:"
  local library="$BUILD_BASE/libs/libpolar_ssl.a"
  local archs_found=$(get_architecture_from_binary "$library")

  echo "Architectures supported: $archs_found"
  test_architecture_wanted_vs_got \
    libpolar_ssl "$BUILD_APP_ARCHS" "$archs_found" WARNING
}


#:# echo 'Defining function werner_zrtp_prepare()'
function werner_zrtp_prepare()
{
  pushd "$BUILD_BASE/support"  > /dev/null

  # if missing, create link 
  if [ ! -e zrtp ]
  then
    ln -s zrtpcpp zrtp
  fi

  popd > /dev/null
}


#:# echo 'Defining function werner_zrtp_build()'
function werner_zrtp_build()
{
  local project_name="werner_zrtp"
  local project="$project_name"".xcodeproj"
  local directory="support/werner_zrtp"
  local logfile="$BUILD_BASE""/xcodebuild_""$project_name"".log"

  pushd $directory > /dev/null

  echo "! Describing ${project_name}:"
  xcodebuild -list -project $project
  echo

  echo "! Building ${project_name}:"
  set -x
  xcodebuild -verbose                                        \
             -project $project                               \
             -sdk iphoneos                                   \
             -configuration $BUILD_CONFIGURATION clean build \
             $BUILD_OPTIONS                                  \
             ARCHS="$BUILD_APP_ARCHS"                        \
  >| $logfile

  local status=$?
  set +x
  handle_xcodebuild_result $status "$project_name" "$logfile" ERROR_IS_FATAL

  popd > /dev/null
}


#:# echo 'Defining function werner_zrtp_post()'
function werner_zrtp_post()
{
  local source="$BUILD_BASE/support/werner_zrtp/build/$BUILD_CONFIGURATION-iphoneos/libwerner_zrtp.a"
  echo "! Copying libwerner_zrtp.a to libs/:"
  cp "$source" $BUILD_BASE/libs || failed "Cannot install libwerner_zrtp.a ."
}


#:# echo 'Defining function werner_zrtp_verify()'
function werner_zrtp_verify()
{
  echo "! Verifying libwerner_zrtp.a:"
  local library="$BUILD_BASE/libs/libwerner_zrtp.a"
  local archs_found=$(get_architecture_from_binary "$library")

  echo "Architectures supported: $archs_found"
  test_architecture_wanted_vs_got \
    libwerner_zrtp "$BUILD_APP_ARCHS" "$archs_found" WARNING
}


# This builds an archive that has what we'll eventually want in our various IPAs.
# This archive would not be accepted by the Apple Store. This is a Safety Feature.
#:# echo "Defining function build_archive()"
function build_archive()
{
  local project="$PROJECT_NAME.xcodeproj"
  local logfile="$BUILD_BASE""/xcodebuild_""$PROJECT_NAME"".log"

  pushd "$BUILD_APP_VOIPPHONE_DIR" > /dev/null

  echo "! Describing ${PROJECT_NAME}:"
  xcodebuild -list -project $project
  echo

  local    hPath="$BUILD_BASE""/support/zrtpcpp/clients/tivi";
  hPath="$hPath ""$BUILD_BASE""/support/zrtpcpp";
  hPath="$hPath ""$BUILD_BASE""/support/zrtpcpp/zrtp";
  hPath="$hPath ""$BUILD_BASE""/support/polarssl/include";

# The flags below disable code signing. If signing is not forcibly disabled,
# the code is signed automatically by Apple looking up and applying previously
# used credentials cached in undocumented places.
#
#             CODE_SIGN_IDENTITY=""                                  \
#             CODE_SIGNING_REQUIRED=NO                               \


  echo "! Building ${PROJECT_NAME}:"
  set -x
  xcodebuild -verbose                                                \
             -scheme        $PROJECT_NAME                            \
             -sdk           iphoneos                                 \
             -workspace     $PROJECT_WORKSPACE                       \
             -configuration $BUILD_CONFIGURATION clean build archive \
             -archivePath   $BUILD_ARCHIVE_PATH                      \
             CODE_SIGN_IDENTITY=""                                   \
             CODE_SIGNING_REQUIRED=NO                                \
             $BUILD_OPTIONS                                          \
             HEADER_SEARCH_PATHS="$hPath"                            \
             LIBRARY_SEARCH_PATHS="$BUILD_BASE/libs"                 \
             ARCHS="$BUILD_APP_ARCHS"                                \
  >| $logfile

  local status=$?
  set +x
  handle_xcodebuild_result $status "$PROJECT_NAME" "$logfile" ERROR_IS_FATAL

  popd > /dev/null
}


# It would be nice to modify the CFBundleVersion in apple/ios/VoipPhone/VoipPhone-Info.plist
# before building the archive, and let xcodebuild copy in the desired bundle ID. Unfortunately
# a hook (in the .pbxproj file) destroys that value. Therefore this must be called after the
# archive has been built.
#:# echo "Defining function set_build_version()"
function set_build_version()
{
  local archive_plist="$BUILD_ARCHIVE_PATH/Info.plist"
  # BUILD_VERSION_PREFIX - defined by the release engineer in Jenkins build exec shell
  # BUILD_NUMBER from Jenkins
  BUILD_VERSION_ID="$BUILD_VERSION_PREFIX$BUILD_NUMBER"

  echo "! Displaying pre-existing CFBundleVersion and then changing to '$BUILD_VERSION_ID':"

  echo -n 'Pre-existing CFBundleVersion is: '
  /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" $archive_plist

  /usr/libexec/PlistBuddy -c "Set :ApplicationProperties:CFBundleVersion $BUILD_VERSION_ID" $archive_plist

  echo -n 'CFBundleVersion is now set to: '
  /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" $archive_plist
}


# This is parameterized, and the Jenkins workspace contents carefully
# structured, to support building multiple xcarchives.
# Arg1 is the .xcarchive to be verified.
# Arg2 is "signed" if archive signature validity should be verified.
#:# echo "Defining function verify_archive()"
function verify_archive()
{
  local xcarchive="$1"

  echo '! Displaying and checking bundle version:'

  local archivePlist="$xcarchive/Info.plist"
  local bundleVersion=`/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" $archivePlist`
  echo "Archive bundle version: $bundleVersion"

  # Verify the archive has the BUILD_VERSION_ID of the app just built
  if [ "$BUILD_VERSION_ID" != "$bundleVersion" ]
  then
    failed "verify_archive wants version $BUILD_VERSION_ID got $bundleVersion."
  fi

  echo '! Displaying and checking architectures supported by archive:'

  # List the hardware architectures supported by the xcarchive
  local archive_app="$xcarchive/Products/Applications/$BUILD_APP_NAME.app"
  local archive_archs=`xcrun -sdk iphoneos lipo -info "$archive_app/$BUILD_APP_NAME"`
  echo "$archive_archs"

  # Abort build if archive does not match what was expected
  local archs_only=`expr "$archive_archs" : '.*:\(.*\)'`
        archs_only="${archs_only%"${archs_only##*[![:space:]]}"}"
        archs_only="${archs_only#"${archs_only%%[![:space:]]*}"}"
  test_architecture_wanted_vs_got \
    archive "$BUILD_APP_ARCHS" "$archs_only" ABORT

  echo
  verify_app "$BUILD_APP_NAME.app in archive" "$archive_app" "$2"
}

# Common code to verify an app, displaying its entitlements and signature.
# Arg1 is the entity to be verified, for log messages.
# Arg2 is the path to the .app to verify; may be in a Payload or .xcarchive .
# Arg3 is "signed" if archive signature validity should be displayed/verified;
#      if arg3 is not "signed", signature presence is treated as a fatal error.
#:# echo "Defining function verify_app()"
function verify_app()
{
  local entity="$1"
  local app_path="$2"
  local signed="$3"
  local mpfile="$app_path/embedded.mobileprovision"

  if [ "$signed" == 'signed' ]
  then
    echo "! Displaying details of ${entity}:"
    echo "  Signature:"
    codesign -d --verbose=4 --file-list - "$app_path" 2>&1 | sed 's/^/    /'
    echo
    echo "  Entitlements:"
    codesign -d --entitlements :- "$app_path" 2>&1 | sed 's/^/    /'
    echo
    echo "  Contents of $mpfile of ${entity}:"
    if [ -r "$mpfile" ]
    then
      echo "    Entitlements:"
      security cms -D  -i "$mpfile" | plutil -extract Entitlements xml1 -o - - | sed 's/^/      /'
      echo "    Provisioning Profile:"
      local provName=`awk -F '[<>]' '/<key>Name</{getline; print $3}' "$mpfile"`
      local provUUID=`awk -F '[<>]' '/<key>UUID</{getline; print $3}' "$mpfile"`
      echo "      Name: $provName"
      echo "      UUID: $provUUID"
    else
      echo "    $entity has no embedded.mobileprovision file; this is normal for archives."
    fi
    echo
    echo "! Verifying signature of ${entity}:"
    echo 'Result of "strict" verification:'
    codesign --verify --verbose=4               "$app_path"
    local strict_status=$?
    echo
    echo 'Result of "no-strict" verification:'
    codesign --verify --verbose=4  --no-strict  "$app_path"
    local nostrict_status=$?
    echo
    local status=$strict_status
    if [ $status -ne 0 ] && [ "$CODESIGN_VERIFY" == 'NOSTRICT' ]
    then
      echo 'Applying CODESIGN_VERIFY=NOSTRICT !'
      status=$nostrict_status
    fi
    handle_codesign_result $status "Verifying signature of $entity"
  else
    echo "! Confirming $entity is unsigned:"
    codesign --verify --verbose=4 "$app_path"
    local status=$?
    if [ $status -eq 0 ]
    then
      failed "$entity should be unsigned but is signed."
    fi
  fi
}


# This is parameterized, and Jenkins workspace contents carefully structured, to
# support building multiple IPAs using the same common technique. It works by
# copying the unsigned archive, modifying its bundle ID if necessary, signing
# it, and finally exporting an IPA from it. The passed-in provisioning profile
# entitlements determine whether an enterprise or ad-hoc IPA is produced.
#   Arg1:    full path of .ipa to create
#   Arg2:    workspace subdirectory in which to do this IPA's work
#   Arg3:    IPA profile name
#   Arg4:    signing ID
#   Arg5:    Entitlements path
#   Arg6:    bundle ID to set, if any, else ''
#   Arg7:    bundle Display Name to set, if any, else ''
#
#:# echo "Defining function make_ipa_from_archive()"
function make_ipa_from_archive()
{
  local ipa=$1
  local kit=`echo $2|awk -F/ '{print $NF}'`

  mkdir -p -v $2
  pushd       $2 > /dev/null
  touch $kit-make_ipa_from_archive.began

  local ipa_archive_path="$(pwd)/$kit.xcarchive"
  local logfile="$kit-make_ipa_from_archive.log"
  local arc_app="$ipa_archive_path/Products/Applications/$BUILD_APP_NAME.app"
  local profile_name="$3"
  local signing_id="$4"
  local entitlements_path="$5"

  cat <<-EOF
	! Initially copying from:
	    $BUILD_ARCHIVE_PATH
	! Mutating then exporting from:
	    $ipa_archive_path
	! Using profile file selected by xcodebuild based on profile name:
	    $profile_name
	! Finally producing:
	    $ipa

EOF

  # Make a local copy of the unsigned archive
  cp -r "$BUILD_ARCHIVE_PATH" "$ipa_archive_path"

  # If requested, replace the bundle identifier and display name
  if [ -n "$6" ] && [ -n "$7" ]
  then
    echo "! Replacing '$kit' IPA's Bundle Identifier and Display Name:"
    $PlistBuddy -c "Set :CFBundleIdentifier  $6" "$arc_app/Info.plist"
    $PlistBuddy -c "Set :CFBundleDisplayName $7" "$arc_app/Info.plist"
  fi

  # Sign the archive which appends the entitlements to the program binary
  echo "! Forcibly signing the '$kit' archive:"
  codesign -f --verbose=4                      \
           --sign "$signing_id"                \
           --entitlements "$entitlements_path" \
           "$arc_app"
  handle_codesign_result $? "Signing '$kit' ipa"

  # Export the ipa from the archive
  echo "! Exporting to '$kit' IPA:"
  set -x
  xcodebuild -verbose                                   \
             -exportArchive                             \
             -exportFormat ipa                          \
             -archivePath "$ipa_archive_path"           \
             -exportPath "$ipa"                         \
             -exportProvisioningProfile "$profile_name" \
  >| $logfile

  local status=$?
  set +x
  handle_xcodebuild_result $status "archive export for '$kit' ipa" "$logfile" TOLERATE_ERROR

  touch $kit-make_ipa_from_archive.ended
  popd > /dev/null
}


# This is parameterized, and Jenkins workspace contents carefully structured,
# to support building multiple IPAs.
# $1 - path to IPA file
# $2 - path to kit subdirectory
#:# echo "Defining function verify_ipa()"
function verify_ipa()
{
  local ipa=$1
  local kit=`echo $2|awk -F/ '{print $NF}'`

  mkdir -p -v "$2/vfy"
  pushd "$2/vfy" > /dev/null
  touch $kit-verify_ipa.began

  unzip -q "$ipa"
  
  verify_app "$BUILD_APP_NAME.app in '$kit' IPA" "Payload/$BUILD_APP_NAME.app" "signed"

  touch $kit-verify_ipa.ended
  popd > /dev/null
}


#:# echo "Defining function make_store_archive_from_archive()"
function make_store_archive_from_archive()
{
  mkdir -p -v $BUILD_KIT_STORE
  pushd       $BUILD_KIT_STORE > /dev/null
  touch make_store_archive_from_archive.began

  # make a local copy of the archive
  echo "! Copying the archive:"
  cp -R "$BUILD_ARCHIVE_PATH" "$STORE_ARCHIVE_PATH"

  local arc_app="$STORE_ARCHIVE_PATH/Products/Applications/$BUILD_APP_NAME.app"

  # Sign the archive which appends the entitlements to the program binary
  echo "! Forcibly signing the archive:"
  codesign -f --verbose=4 --sign "$STORE_SIGNING_ID" \
           --entitlements "$STORE_ENTITLEMENTS_PATH" \
           "$arc_app"
  handle_codesign_result $? "Signing store archive"

  touch make_store_archive_from_archive.ended
  popd > /dev/null
}


### FOR POSSIBLE FUTURE USE ###
# $1 - compare base's name
# $2 - compare target's name
#:# echo 'Defining function compare_payloads()'
function compare_payloads()
{
  local bKit="$1"
  local dKit="$2"
  local bPath="$1"
  local dPath="$2/vfy"
  local diffOut="$dPath/${bKit}_differences.txt"
  pushd "$BUILD_KITS" > /dev/null

  echo
  echo "! Comparing verified $dKit to $bKit, i.e. these two directories:"
  # ls "rt" options below sort by increasing modification date, so older first
  ls -FLTldrt \
      "$bPath/Payload/$PROJECT_NAME.app" \
      "$dPath/Payload/$PROJECT_NAME.app" \
    | sed 's/^/    /'

  diff -qr \
      "$bPath/Payload/$PROJECT_NAME.app" \
      "$dPath/Payload/$PROJECT_NAME.app" \
    > $diffOut
  if [ $? -lt 2 ]
  then
    diffCount=`grep -c . $diffOut`
    case $diffCount in
    (0)
      echo "  All $dKit kit $PROJECT_NAME.app files are identical to the $bKit kit's."
      ;;
    (1)
      echo "  1 $dKit kit $PROJECT_NAME.app file differs from the $bKit kit's:"
      ;;
    ([2-5])
      echo "  $diffCount $dKit kit $PROJECT_NAME.app files differ from the $bKit kit's:"
      ;;
    (*)
      echo "  WARNING: $diffCount $dKit kit $PROJECT_NAME.app files differ from the $bKit kit's."
      echo "  The full list is in $diffOut. The first 5 are:"
      ;;
    esac
    head -5 $diffOut | sed 's/^/  /'
  else
    echo '? Could not compare kits.'
  fi

  popd > /dev/null
}



echo_in_box 'Validating Build Root:'
validate_build_root
echo

if [ -n "$MAKING_ADHOC_IPA" ] || [ -n "$MAKING_ENTERPRISE_IPA" ] || [ -n "$MAKING_STORE_ARCHIVE" ]
then
  echo_in_box 'Describing Keychain:'
  describe_keychain
fi

echo_in_box 'Describing Environment:'
describe_environment
echo

echo_in_box 'Describing SDKs:'
describe_sdks

echo_in_box 'Describing Schemes:'
describe_schemes
echo

echo_in_box 'Describing Xcode Workspace:'
describe_xcode_workspace

echo_in_box 'Preparing For Build:'
build_prepare
echo

echo_in_box 'Building polar_ssl Submodule:'
polarssl_build
polarssl_post
polarssl_verify
echo

echo_in_box 'Building werner_zrtp Submodule:'
werner_zrtp_prepare
werner_zrtp_build
werner_zrtp_post
werner_zrtp_verify
echo

echo_in_box 'Building Silent Phone App Archive:'
build_archive

echo_in_box 'Setting Build Version:'
set_build_version
echo

echo_in_box 'Verifying Archive:'
verify_archive "$BUILD_ARCHIVE_PATH" 'unsigned'
echo

if [ $MAKING_ADHOC_IPA ]
then
  echo_in_box 'Making Ad-Hoc IPA from Archive:'
  make_ipa_from_archive              \
    "$BUILD_ADHOC_IPA"               \
    "$BUILD_KIT_ADHOC"               \
    "$ADHOC_IPA_PROFILE_NAME"        \
    "$ADHOC_SIGNING_ID"              \
    "$ADHOC_ENTITLEMENTS_PATH"       \
    ''                               \
    ''
  echo_in_box 'Verifying Ad-Hoc IPA:'
  verify_ipa "$BUILD_ADHOC_IPA" "$BUILD_KIT_ADHOC"
  echo
fi

if [ $MAKING_ENTERPRISE_IPA ]
then
  echo_in_box 'Making Enterprise IPA from Archive:'
  make_ipa_from_archive              \
    "$BUILD_ENTER_IPA"               \
    "$BUILD_KIT_ENTER"               \
    "$ENTER_IPA_PROFILE_NAME"        \
    "$ENTER_SIGNING_ID"              \
    "$ENTER_ENTITLEMENTS_PATH"       \
    "$ENTER_IPA_BUNDLE_ID"           \
    "$ENTER_IPA_BUNDLE_DISPLAY_NAME"
  echo_in_box 'Verifying Enterprise IPA:'
  verify_ipa "$BUILD_ENTER_IPA" "$BUILD_KIT_ENTER"
  echo
fi

if [ $MAKING_STORE_ARCHIVE ]
then
  echo_in_box 'Making Store Archive from Archive:'
  echo
  make_store_archive_from_archive
  echo
  echo_in_box 'Verifying Store Archive:'
  echo
  verify_archive "$STORE_ARCHIVE_PATH" 'signed'
  echo
fi

#echo_in_box 'Comparing Verified IPA To Archive:'
#echo
#compare_payloads base ent
#echo


echo_in_box "Build Phase Completed! Errors:$errorCount."

echo "Errors:$errorCount" >| errorCount.txt

exit $[ errorCount > 0 ]