#!/usr/bin/env ruby
# frozen_string_literal: true

# Optional Mac developer helper: run Tesseract (C++ engine) on a scan for comparison
# with on-device Apple Vision OCR. Does not ship in the iOS app.
#
# Usage: ruby scripts/dev_ocr_compare.rb path/to/scan.png
# Requires: brew install tesseract (optional)

path = ARGV[0]
abort "Usage: #{$PROGRAM_NAME} <image.png>" unless path && File.file?(path)

def which(cmd)
  ex = ENV["PATH"].split(File::PATH_SEPARATOR).map { |p| File.join(p, cmd) }.find { |f| File.executable?(f) }
  ex || ""
end

ts = which("tesseract")
if ts.empty?
  warn "tesseract not found in PATH. Install with: brew install tesseract"
  warn "The iOS app uses Apple Vision (native); this script is only for desktop comparison."
  exit 1
end

require "tmpdir"
Dir.mktmpdir("ocr_compare") do |dir|
  txt = File.join(dir, "out")
  ok = system(ts, path, txt, "-l", "eng")
  abort "tesseract failed" unless ok
  puts File.read("#{txt}.txt")
end
