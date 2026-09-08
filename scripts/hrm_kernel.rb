#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

require_relative "../lib/hrm_kernel/store"

module HrmKernel
  module CLI
    ROLES = %w[orchestrator worker operator reviewer].freeze
    MAX_INPUT_BYTES = 4 * 1024 * 1024

    module_function

    def run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      command = argv.shift
      return print_help(stdout, 0) if command.nil? || command == "--help" || command == "-h"

      output = case command
               when "apply" then apply(argv, stdin)
               when "status" then status(argv)
               when "verify" then verify(argv)
               else
                 raise HrmKernel::Error, "unknown command #{command.inspect}"
               end
      stdout.puts(JSON.generate(output))
      0
    rescue HrmKernel::Error, OptionParser::ParseError, JSON::ParserError, SystemCallError => e
      failure = { "error" => e.message }
      failure["code"] = if e.is_a?(HrmKernel::Error)
                          e.code
                        elsif e.is_a?(SystemCallError)
                          "io_error"
                        else
                          "invalid_input"
                        end
      failure["details"] = e.details if e.is_a?(HrmKernel::Error) && e.details
      stderr.puts(JSON.generate(failure))
      1
    end

    def apply(argv, stdin)
      options = parse_options(argv, input: true)
      input = options.fetch(:input)
      json = if input == "-"
               read_bounded(stdin, "standard input")
             else
               File.open(input, "r:UTF-8") { |file| read_bounded(file, input) }
             end
      parsed = JSON.parse(json)
      raise HrmKernel::Error, "input must be a JSON object" unless parsed.is_a?(Hash)

      Store.new(options.fetch(:state_dir)).transact(parsed)
    end

    def status(argv)
      options = parse_options(argv, role: true)
      Store.new(options.fetch(:state_dir)).project(
        role: options.fetch(:role),
        actor_id: options[:actor_id]
      )
    end

    def verify(argv)
      options = parse_options(argv)
      Store.new(options.fetch(:state_dir)).verify!
    end

    def parse_options(argv, input: false, role: false)
      options = {}
      parser = OptionParser.new do |opts|
        opts.on("--state-dir DIR") { |value| options[:state_dir] = value }
        opts.on("--input FILE") { |value| options[:input] = value } if input
        if role
          opts.on("--role ROLE") { |value| options[:role] = value }
          opts.on("--actor-id ID") { |value| options[:actor_id] = value }
        end
        opts.on("-h", "--help") do
          raise HrmKernel::Error, "use top-level --help for usage"
        end
      end
      parser.parse!(argv)
      raise OptionParser::ParseError, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      raise OptionParser::MissingArgument, "--state-dir" unless options[:state_dir]
      raise OptionParser::MissingArgument, "--input" if input && !options[:input]
      if role
        raise OptionParser::MissingArgument, "--role" unless options[:role]
        unless ROLES.include?(options[:role])
          raise OptionParser::InvalidArgument, "--role must be one of #{ROLES.join(', ')}"
        end
      end
      options
    end

    def read_bounded(input, label)
      contents = input.read(MAX_INPUT_BYTES + 1)
      raise HrmKernel::Error, "#{label} exceeds #{MAX_INPUT_BYTES} bytes" if contents.bytesize > MAX_INPUT_BYTES

      contents
    end

    def print_help(output, status)
      output.puts <<~HELP
        Usage:
          ruby scripts/hrm_kernel.rb apply --state-dir DIR --input JSONFILE
          ruby scripts/hrm_kernel.rb apply --state-dir DIR --input -
          ruby scripts/hrm_kernel.rb status --state-dir DIR --role orchestrator|worker|operator|reviewer [--actor-id ID]
          ruby scripts/hrm_kernel.rb verify --state-dir DIR

        This CLI trusts the local caller's asserted actor identity. It does not authenticate it.
      HELP
      status
    end
  end
end

exit(HrmKernel::CLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
