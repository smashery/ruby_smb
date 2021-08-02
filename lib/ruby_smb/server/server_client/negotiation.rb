require 'securerandom'

module RubySMB
  class Server
    class ServerClient
      module Negotiation
        def handle_negotiate(raw_request)
          case raw_request[0...4]
          when "\xff\x53\x4d\x42".b
            handle_negotiate_smb1(raw_request)
          when "\xfe\x53\x4d\x42".b
            handle_negotiate_smb2(raw_request)
          else
            disconnect!
          end
        end

        def handle_negotiate_smb1(raw_request)
          request = SMB1::Packet::NegotiateRequest.read(raw_request)

          unless request.dialects.map(&:dialect_string).include?(Client::SMB1_DIALECT_SMB2_WILDCARD)
            # SMB1 is not supported yet
            response = SMB1::Packet::NegotiateResponse.new
            response.parameter_block.word_count = 1
            response.parameter_block.dialect_index = 0xffff
            response.data_block.byte_count = 0
            send_packet(response)
            disconnect!
            return
          end

          response = SMB2::Packet::NegotiateResponse.new
          response.smb2_header.credits = 1
          response.security_mode.signing_enabled = 1
          response.dialect_revision = 0x02ff
          response.server_guid = @server.server_guid

          response.max_transact_size = 0x800000
          response.max_read_size = 0x800000
          response.max_write_size = 0x800000
          response.system_time.set(Time.now)
          response.security_buffer_offset = response.security_buffer.abs_offset
          response.security_buffer = process_gss.buffer

          send_packet(response)
        end

        def handle_negotiate_smb2(raw_request)
          request = SMB2::Packet::NegotiateRequest.read(raw_request)

          #dialect = ([0x311, 0x302, 0x300, 0x210, 0x202] & request.dialects.map(&:to_i)).sort.last
          # todo: support newer than 3.0.2
          dialect = ([0x302, 0x300, 0x210, 0x202] & request.dialects.map(&:to_i)).sort.last
          if dialect.nil?
            # todo: respond with an appropriate error when no dialect is supported
            disconnect!
            return
          end

          response = SMB2::Packet::NegotiateResponse.new
          response.smb2_header.credits = 1
          response.security_mode.signing_enabled = 1
          response.dialect_revision = dialect
          response.server_guid = @server.server_guid

          response.max_transact_size = 0x800000
          response.max_read_size = 0x800000
          response.max_write_size = 0x800000
          response.system_time.set(Time.now)

          response.security_buffer_offset = response.security_buffer.abs_offset
          response.security_buffer = process_gss.buffer

          response.negotiate_context_offset = response.negotiate_context_list.abs_offset
          if dialect == 0x311
            response.add_negotiate_context(SMB2::NegotiateContext.new(
              context_type: SMB2::NegotiateContext::SMB2_PREAUTH_INTEGRITY_CAPABILITIES,
              data: SMB2::PreauthIntegrityCapabilities.new(
                hash_algorithms: [ SMB2::PreauthIntegrityCapabilities::SHA_512 ],
                salt: SecureRandom.random_bytes(32))
            ))
            response.add_negotiate_context(SMB2::NegotiateContext.new(
              context_type: SMB2::NegotiateContext::SMB2_ENCRYPTION_CAPABILITIES,
              data: SMB2::EncryptionCapabilities.new(
                # todo: Windows Server 2019 only returns AES-128-CCM but we should support GCM too
                ciphers: [ SMB2::EncryptionCapabilities::AES_128_CCM ]
              )
            ))
          end

          send_packet(response)
          @state = :session_setup
          @dialect = dialect
        end
      end
    end
  end
end
