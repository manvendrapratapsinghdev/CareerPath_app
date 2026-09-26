Pod::Spec.new do |s|
  s.name             = 'live_audio'
  s.version          = '1.0.0'
  s.summary          = 'Native PCM capture and playback with voice processing.'
  s.description      = 'Native 24 kHz PCM16 capture and playback with echo cancellation.'
  s.homepage         = 'https://example.invalid/live_audio'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'CareerPath' => 'dev@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
