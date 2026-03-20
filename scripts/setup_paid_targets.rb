#!/usr/bin/env ruby
# frozen_string_literal: true

# setup_paid_targets.rb — duplicate the Quartz app target for per-platform App Store pricing
#
# Manual edits to project.pbxproj are error-prone; this script uses the CocoaPods `xcodeproj` gem
# to clone the main `Quartz` target into:
#   - `Quartz iOS`  → PRODUCT_BUNDLE_IDENTIFIER = com.yourname.quartz.ios
#   - `Quartz Mac`  → PRODUCT_BUNDLE_IDENTIFIER = com.yourname.quartz.mac
#
# Prerequisites:
#   gem install xcodeproj
#
# Run from the repository root:
#   ruby scripts/setup_paid_targets.rb
#
# After running, open Quartz.xcodeproj in Xcode, verify build settings, signing, schemes, and
# App Store Connect records for each bundle ID. Re-run only if you need to recreate targets;
# duplicate names will fail — remove existing `Quartz iOS` / `Quartz Mac` targets first if present.

require 'xcodeproj'

REPO_ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(REPO_ROOT, 'Quartz.xcodeproj')

IOS_NAME = 'Quartz iOS'
MAC_NAME = 'Quartz Mac'
IOS_BUNDLE = 'com.yourname.quartz.ios'
MAC_BUNDLE = 'com.yourname.quartz.mac'
SOURCE_TARGET_NAME = 'Quartz'

def copy_build_settings(source_target, dest_target, bundle_id, platform)
  dest_target.build_configuration_list.build_configurations.each do |dest_conf|
    source_conf = source_target.build_configuration_list.build_configurations.find { |c| c.name == dest_conf.name }
    next unless source_conf

    source_conf.build_settings.each do |key, value|
      dest_conf.build_settings[key] = value
    end

    dest_conf.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    dest_conf.build_settings['PRODUCT_NAME'] = "$(TARGET_NAME)"

    case platform
    when :ios
      dest_conf.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
      dest_conf.build_settings['SDKROOT'] = 'iphoneos'
      dest_conf.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
      dest_conf.build_settings.delete('MACOSX_DEPLOYMENT_TARGET')
    when :macos
      dest_conf.build_settings['SUPPORTED_PLATFORMS'] = 'macosx'
      dest_conf.build_settings['SDKROOT'] = 'macosx'
      dest_conf.build_settings.delete('IPHONEOS_DEPLOYMENT_TARGET')
      dest_conf.build_settings.delete('TARGETED_DEVICE_FAMILY')
    end
  end
end

def attach_synchronized_groups(source_target, dest_target)
  return unless source_target.respond_to?(:file_system_synchronized_groups)
  return unless dest_target.respond_to?(:file_system_synchronized_groups) && dest_target.respond_to?(:file_system_synchronized_groups=)

  groups = source_target.file_system_synchronized_groups
  return if groups.nil? || groups.empty?

  existing = dest_target.file_system_synchronized_groups || []
  groups.each do |g|
    existing << g unless existing.include?(g)
  end
  dest_target.file_system_synchronized_groups = existing
end

def attach_package_products(source_target, dest_target)
  return unless source_target.respond_to?(:package_product_dependencies)
  return unless dest_target.respond_to?(:package_product_dependencies) && dest_target.respond_to?(:package_product_dependencies=)

  existing = dest_target.package_product_dependencies || []
  source_target.package_product_dependencies.each do |dep|
    existing << dep unless existing.include?(dep)
  end
  dest_target.package_product_dependencies = existing
end

def duplicate_from_source(project, source_target, name, bundle_id, platform)
  if project.targets.any? { |t| t.name == name }
    warn "Target #{name.inspect} already exists — skipping."
    return
  end

  # :ios / :osx are the platforms supported by Xcodeproj::Project#new_target
  xcodeproj_platform = platform == :ios ? :ios : :osx
  new_target = project.new_target(:application, name, xcodeproj_platform)

  copy_build_settings(source_target, new_target, bundle_id, platform)
  attach_synchronized_groups(source_target, new_target)
  attach_package_products(source_target, new_target)

  new_target.product_name = name
  new_target
end

unless File.directory?(PROJECT_PATH)
  warn "Project not found at #{PROJECT_PATH}"
  exit 1
end

project = Xcodeproj::Project.open(PROJECT_PATH)
source = project.targets.find { |t| t.name == SOURCE_TARGET_NAME }

unless source
  warn "Could not find source target #{SOURCE_TARGET_NAME.inspect}"
  exit 1
end

duplicate_from_source(project, source, IOS_NAME, IOS_BUNDLE, :ios)
duplicate_from_source(project, source, MAC_NAME, MAC_BUNDLE, :macos)

project.save
puts 'Updated Quartz.xcodeproj — added (or attempted) Quartz iOS / Quartz Mac targets.'
puts "Bundle IDs: #{IOS_BUNDLE}, #{MAC_BUNDLE}"
puts 'Review schemes, signing, and test targets in Xcode before shipping.'
