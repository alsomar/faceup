module ASM_Extensions
  module FaceUp

    # Metadata
    INFO_NAME    = "FaceUp"
    INFO_AUTHOR  = "Alejandro Soriano"
    INFO_VERSION = EXTENSION[:version].to_s.freeze
    INFO_UPDATE  = EXTENSION[:update].to_s.freeze
    INFO_START   = EXTENSION[:dev_start].to_s.freeze

    # Copyright range: dev_start year to current year
    copy_start   = INFO_START[/\d{4}/]&.to_i || 2023
    copy_year    = Time.now.year rescue nil
    copy_range   =
      if copy_year.nil?
        "#{copy_start}-Now"
      elsif copy_year > copy_start
        "#{copy_start}-#{copy_year}"
      else
        copy_start.to_s
      end

    INFO_COPY    = "\u00A9 #{INFO_AUTHOR}, #{copy_range}".freeze

  end # module FaceUp
end # module ASM_Extensions
