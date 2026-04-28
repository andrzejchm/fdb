Pod::Spec.new do |s|
  s.name             = 'fdb_helper'
  s.version          = '1.2.1'
  s.summary          = 'fdb_helper Flutter plugin — native tap injection and VM service extensions.'
  s.homepage         = 'https://pub.dev/packages/fdb_helper'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'fdb' => 'fdb@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
