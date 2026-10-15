# frozen_string_literal: true

require "shellwords"

module DocsKit
  # Screenshots a URL into the site's OG/Twitter images. Loaded ONLY by the
  # host-installed `docs_kit:og` rake task (via an explicit require) — never at
  # gem runtime — so the headless-browser tooling it drives is never a docs-kit
  # dependency. zeitwerk ignores this file (see lib/docs_kit.rb) for the same
  # reason: it must not be eager-loaded into a host that never runs the task.
  #
  # Usage (from the rake task):
  #   DocsKit::OgGenerator.new(url:, out_dir:, sizes:, shooter:).call
  #
  # When #url is nil the generator boots the Rails app on an ephemeral port and
  # shoots "/"; when set it shoots that URL directly (e.g. a deployed site). The
  # shooter is a headless-browser CLI resolved at runtime: an explicit override,
  # else the first of shot-scraper / chromium / chrome found on PATH.
  class OgGenerator
    # Raised when no supported headless-browser CLI is available. The message
    # names each supported tool + how to install one, so the task fails with a
    # fix, not a stack trace.
    class NoShooterError < StandardError; end

    # The shooters we know how to drive, in preference order. shot-scraper first
    # (purpose-built, handles sizing cleanly); then a raw chromium/chrome.
    SHOOTERS = %w[shot-scraper chromium chromium-browser google-chrome chrome].freeze

    attr_reader :url, :out_dir, :sizes

    def initialize(url:, out_dir:, sizes:, shooter: nil)
      @url = url
      @out_dir = out_dir.to_s
      @sizes = sizes
      @shooter = shooter
    end

    # The chosen shooter name (explicit override or nil until #resolve_shooter!).
    def shooter_name = @shooter

    # The full run: resolve a shooter, ensure the output dir, boot a local server
    # if needed, and shoot every size. Returns the list of written paths.
    def call
      tool = resolve_shooter!
      require "fileutils"
      FileUtils.mkdir_p(out_dir)

      with_target_url do |target|
        sizes.map do |filename, dimensions|
          path = File.join(out_dir, filename)
          run(command_for(tool, target, dimensions, path))
          path
        end
      end
    end

    # Resolve the shooter CLI: an explicit override (returned as-is so a user can
    # force a specific tool), else the first supported binary on PATH. Raises
    # NoShooterError naming the options when none is found.
    def resolve_shooter!
      return @shooter if @shooter && !@shooter.to_s.empty?

      found = SHOOTERS.find { |cmd| which(cmd) }
      return found if found

      raise NoShooterError,
            "No headless-browser CLI found. Install one of: shot-scraper " \
            "(`pipx install shot-scraper && shot-scraper install`), chromium, or " \
            "chrome — or set DOCS_KIT_SHOT to the command to use."
    end

    # Build the argv for `tool` to screenshot `target` at `[w, h]` into `path`.
    # Kept pure (no side effects) so it's unit-testable without a browser.
    def command_for(tool, target, dimensions, path)
      width, height = dimensions
      case tool
      when "shot-scraper"
        ["shot-scraper", target, "--width", width.to_s, "--height", height.to_s, "-o", path]
      else # a chromium/chrome family binary
        [
          tool, "--headless=new", "--disable-gpu", "--hide-scrollbars",
          "--force-device-scale-factor=1",
          "--window-size=#{width},#{height}",
          "--screenshot=#{path}", target
        ]
      end
    end

    private

    # Yield the URL to shoot. If #url was given, shoot it directly. Otherwise boot
    # the host Rails app on an ephemeral port, yield its local URL, and tear it
    # down after. Rack/rackup are the host app's own deps (it's a Rails app), not
    # docs-kit's — required lazily here so the gem never loads them.
    def with_target_url(&)
      return yield(url) if url && !url.to_s.empty?

      boot_local_server(&)
    end

    # Boot the Rails app with Rack::Handler on an ephemeral port in a background
    # thread, wait for it to answer, yield the URL, then shut down.
    def boot_local_server
      require "rack"
      require "socket"

      port = free_port
      app = Rails.application
      # The docs_kit:og rake task's one-shot local server (a CLI, never a request
      # path): one thread, killed in the ensure below.
      server_thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
        Rackup::Handler.get("webrick").run(app, Port: port, Host: "127.0.0.1", Logger: null_logger, AccessLog: [])
      rescue LoadError
        Rack::Handler.get("webrick").run(app, Port: port, Host: "127.0.0.1", Logger: null_logger, AccessLog: [])
      end
      wait_for_port(port)
      yield "http://127.0.0.1:#{port}/"
    ensure
      server_thread&.kill
    end

    # An open ephemeral port (bind to 0, read it back, close). A tiny race window
    # remains but is acceptable for a one-shot local screenshot server.
    def free_port
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close
      port
    end

    # Poll until the local server accepts a connection (or give up after ~15s so a
    # boot failure surfaces instead of hanging).
    def wait_for_port(port, timeout: 15)
      deadline = monotonic_now + timeout
      loop do
        TCPSocket.new("127.0.0.1", port).close
        return
      rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL
        raise "docs_kit:og: local server did not start within #{timeout}s" if monotonic_now > deadline

        sleep 0.2
      end
    end

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def null_logger
      require "logger"
      Logger.new(File::NULL)
    end

    # Run a command, raising with the joined argv on a non-zero exit so a shooter
    # failure is loud (not a silently-missing image).
    def run(argv)
      ok = system(*argv)
      raise "docs_kit:og: screenshot command failed: #{argv.shelljoin}" unless ok
    end

    # Locate an executable on PATH (a dependency-free `which`), returning its full
    # path or nil. Overridable in specs so shooter resolution is testable.
    def which(cmd)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
        candidate = File.join(dir, cmd)
        return candidate if File.executable?(candidate) && !File.directory?(candidate)
      end
      nil
    end
  end
end
