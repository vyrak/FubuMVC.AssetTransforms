COMPILE_TARGET = ENV['config'].nil? ? "debug" : ENV['config']
CLR_TOOLS_VERSION = "v4.0.30319"

buildsupportfiles = Dir["#{File.dirname(__FILE__)}/buildsupport/*.rb"]

if( ! buildsupportfiles.any? )
  # no buildsupport, let's go get it for them.
  sh 'git submodule update --init' unless buildsupportfiles.any?
  buildsupportfiles = Dir["#{File.dirname(__FILE__)}/buildsupport/*.rb"]
end

# nope, we still don't have buildsupport. Something went wrong.
raise "Run `git submodule update --init` to populate your buildsupport folder." unless buildsupportfiles.any?

buildsupportfiles.each { |ext| load ext }

include FileTest
require 'albacore'
load "VERSION.txt"

RESULTS_DIR = "results"
PRODUCT = "FubuMVC.AssetTransforms"
COPYRIGHT = 'Copyright 2011 The Fubu Team. All rights reserved.';
COMMON_ASSEMBLY_INFO = 'src/CommonAssemblyInfo.cs';
BUILD_DIR = File.expand_path("build")
ARTIFACTS = File.expand_path("artifacts")

@teamcity_build_id = "bt24"
tc_build_number = ENV["BUILD_NUMBER"]
build_revision = tc_build_number || Time.new.strftime('5%H%M')
BUILD_NUMBER = "#{BUILD_VERSION}.#{build_revision}"

props = { :stage => BUILD_DIR, :artifacts => ARTIFACTS }

desc "**Default**, compiles and runs tests"
task :default => [:compile, :unit_test, :bottle_up]

desc "Target used for the CI server"
task :ci => [:update_all_dependencies,:default,:history,:package]

desc "Update the version information for the build"
assemblyinfo :version do |asm|
  asm_version = BUILD_VERSION + ".0"
  
  begin
    commit = `git log -1 --pretty=format:%H`
  rescue
    commit = "git unavailable"
  end
  puts "##teamcity[buildNumber '#{BUILD_NUMBER}']" unless tc_build_number.nil?
  puts "Version: #{BUILD_NUMBER}" if tc_build_number.nil?
  asm.trademark = commit
  asm.product_name = PRODUCT
  asm.description = BUILD_NUMBER
  asm.version = asm_version
  asm.file_version = BUILD_NUMBER
  asm.custom_attributes :AssemblyInformationalVersion => asm_version
  asm.copyright = COPYRIGHT
  asm.output_file = COMMON_ASSEMBLY_INFO
end

desc "Prepares the working directory for a new build"
task :clean => [:update_buildsupport] do
	
	FileUtils.rm_rf props[:stage]
    # work around nasty latency issue where folder still exists for a short while after it is removed
    waitfor { !exists?(props[:stage]) }
	Dir.mkdir props[:stage]
    
	Dir.mkdir props[:artifacts] unless exists?(props[:artifacts])
end

desc "Compiles the libraries"
task :compile => [:restore_if_missing, :clean, :version] do
  MSBuildRunner.compile :compilemode => COMPILE_TARGET, :solutionfile => 'src/FubuMVC.AssetTransforms.sln', :clrversion => CLR_TOOLS_VERSION
end

desc "Make bottles"
task :bottle_up do

  # Coffee ILMerging
  outputDir = "src/FubuMVC.Coffee/bin/#{COMPILE_TARGET}"
  packer = ILRepack.new :out => "#{outputDir}/FubuMVC.Coffee.dll", :lib => outputDir
  packer.merge :lib => outputDir, :refs => ['FubuMVC.Coffee.dll', 'SassAndCoffee.Core.dll', 'SassAndCoffee.JavaScript.dll']
  
  # Less ILMerging
  outputDir = "src/FubuMVC.Less/bin/#{COMPILE_TARGET}"
  packer = ILRepack.new :out => "#{outputDir}/FubuMVC.Less.dll", :lib => outputDir
  packer.merge :lib => outputDir, :refs => ['FubuMVC.Less.dll', 'dotless.Core.dll']

  target = COMPILE_TARGET.downcase
end

desc "Runs unit tests"
task :test => [:unit_test]

desc "Runs unit tests"
task :unit_test => :compile do
  runner = NUnitRunner.new :compilemode => COMPILE_TARGET, :source => 'src', :platform => 'x86'
  runner.executeTests ['FubuMVC.Coffee.Tests', 'FubuMVC.Less.Tests', 'FubuMVC.Sass.Tests', 'FubuMVC.Minifier.Tests']
end

desc "ZIPs up the build results"
zip :package do |zip|
	zip.directories_to_zip = [props[:stage]]
	zip.output_file = 'FubuMVC.AssetTransforms.zip'
	zip.output_path = [props[:artifacts]]
end

def self.fubu(args)
  fubu = Platform.runtime(Nuget.tool("FubuMVC.References", "Fubu.exe"))
  sh "#{fubu} #{args}"
end

# Helpers 

def copyOutputFiles(fromDir, filePattern, outDir)
  Dir.glob(File.join(fromDir, filePattern)){|file| 		
	copy(file, outDir) if File.file?(file)
  } 
end

def waitfor(&block)
  checks = 0
  until block.call || checks >10 
    sleep 0.5
    checks += 1
  end
  raise 'waitfor timeout expired' if checks > 10
end
