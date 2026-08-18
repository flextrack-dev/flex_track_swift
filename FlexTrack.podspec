Pod::Spec.new do |spec|
  spec.name         = "FlexTrack"
  spec.version      = "1.1.0"
  spec.summary      = "Consent-aware, deterministic analytics routing for Swift."
  spec.description  = <<-DESC
    FlexTrack is a provider-agnostic analytics routing SDK for Apple platforms.
    It provides deterministic sampling, consent-aware routing, durable offline
    delivery, selective retry, tracking context, diagnostics, and native Swift
    concurrency safety.
  DESC

  spec.homepage     = "https://github.com/alirezat66/flex_track_swift"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Reza Taghizadeh" => "alirezataghizadeh66@gmail.com" }
  spec.source       = {
    :git => "https://github.com/alirezat66/flex_track_swift.git",
    :tag => spec.version.to_s
  }

  spec.swift_version = "6.2"
  spec.ios.deployment_target = "15.0"
  spec.osx.deployment_target = "12.0"
  spec.source_files = "Sources/FlexTrack/**/*.swift"
  spec.module_name  = "FlexTrack"
end
