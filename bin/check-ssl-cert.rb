#! /usr/bin/env ruby
# frozen_string_literal: false

#
#   check-ssl-cert
#
# DESCRIPTION:
#   Check when a SSL certificate will expire.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   example commands
#
# NOTES:
#   Does it behave differently on specific platforms, specific use cases, etc
#
# LICENSE:
#   Jean-Francois Theroux <me@failshell.io>
#   Nathan Williams <nath.e.will@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'time'
require 'openssl'
require 'sensu-plugin/check/cli'

#
# Check SSL Cert
#
class CheckSSLCert < Sensu::Plugin::Check::CLI
  option :critical,
         description: 'Time (hours or days) left',
         short: '-c',
         long: '--critical TIME',
         required: true

  option :warning,
         description: 'Time (hours or days) left',
         short: '-w',
         long: '--warning TIME',
         required: true

  option :pem,
         description: 'Path to PEM file',
         short: '-P',
         long: '--pem PEM'

  option :host,
         description: 'Host to validate',
         short: '-h',
         long: '--host HOST'

  option :port,
         description: 'Port to validate',
         short: '-p',
         long: '--port PORT'

  option :servername,
         description: 'Set the TLS SNI (Server Name Indication) extension',
         short: '-s',
         long: '--servername SERVER'

  option :pkcs12,
         description: 'Path to PKCS#12 certificate',
         short: '-C',
         long: '--cert P12'

  option :pass,
         description: 'Pass phrase for the private key in PKCS#12 certificate',
         short: '-S',
         long: '--pass '

  option :hours,
         description: 'Calculate expiry in hours, instead of days. Useful for short-lived (<24h) ACME certs',
         short: '-H',
         long: '--hours'

  def ssl_cert_expiry
    `openssl s_client -servername #{config[:servername]} -connect #{config[:host]}:#{config[:port]} < /dev/null 2>&1 | openssl x509 -enddate -noout`.split('=').last
  end

  def ssl_pem_expiry
    OpenSSL::X509::Certificate.new(File.read config[:pem]).not_after # rubocop:disable Style/NestedParenthesizedCalls
  end

  def ssl_pkcs12_expiry
    `openssl pkcs12 -in #{config[:pkcs12]} -nokeys -nomacver -passin pass:"#{config[:pass]}" | openssl x509 -noout -enddate | grep -v MAC`.split('=').last
  end

  def validate_opts
    if !config[:pem] && !config[:pkcs12]
      unknown 'Host and port required' unless config[:host] && config[:port]
    elsif config[:pem]
      unknown 'No such cert' unless File.exist? config[:pem]
    elsif config[:pkcs12]
      if !config[:pass]
        unknown 'No pass phrase specified for PKCS#12 certificate'
      else
        unknown 'No such cert' unless File.exist? config[:pkcs12]
      end
    end
    config[:servername] = config[:host] unless config[:servername]
  end

  def run
    validate_opts

    expiry = if config[:pem]
               ssl_pem_expiry
             elsif config[:pkcs12]
               ssl_pkcs12_expiry
             else
               ssl_cert_expiry
             end

    time_delta = Time.parse(expiry.to_s) - Time.now

    if config[:hours]
      time_delta_check = (time_delta / 3600).floor
      time_check_unit = 'hours'
    else
      time_delta_check = (time_delta / 86_400).floor
      time_check_unit = 'days'
    end

    if time_delta_check < 0 # rubocop:disable Style/NumericPredicate
      critical "Expired #{time_delta_check} #{time_check_unit} ago"
    elsif time_delta_check < config[:critical].to_i
      critical "#{time_delta_check} #{time_check_unit} left"
    elsif time_delta_check < config[:warning].to_i
      warning "#{time_delta_check} #{time_check_unit} left"
    else
      ok "#{time_delta_check} #{time_check_unit} left"
    end
  end
end
