#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/hrm_kernel/host"

if $PROGRAM_NAME == __FILE__
  abort "usage: hrm_host_worker.rb STATE_DIR JOB_ID" unless ARGV.length == 2
  HrmKernel::Host.new(state_dir: ARGV[0]).run_job(job_id: ARGV[1])
end
