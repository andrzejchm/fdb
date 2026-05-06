Pod::Spec.new do |s|
  s.name             = 'fdb_helper'
  s.version          = '1.2.1'
  s.summary          = 'fdb_helper Flutter plugin — native tap injection and VM service extensions.'
  s.homepage         = 'https://pub.dev/packages/fdb_helper'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'fdb' => 'fdb@example.com' }
  s.source           = { :path => '.' }
  s.source_files       = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug]' => '$(inherited) FDB_HELPER_NATIVE_TAP_REAL',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Profile]' => '$(inherited) FDB_HELPER_NATIVE_TAP_REAL',
    'GCC_PREPROCESSOR_DEFINITIONS[config=Debug]' => '$(inherited) FDB_HELPER_NATIVE_TAP_REAL=1',
    'GCC_PREPROCESSOR_DEFINITIONS[config=Profile]' => '$(inherited) FDB_HELPER_NATIVE_TAP_REAL=1',
    'EXCLUDED_SOURCE_FILE_NAMES[config=Release]' => 'FdbHelperNativeTap.m',
  }
  s.swift_version    = '5.0'
end
