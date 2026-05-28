module ASM_Extensions
  module FaceUp

    # Metadata
    INFO_NAME    = "FaceUp"
    INFO_AUTHOR  = "Alejandro Soriano"
    INFO_VERSION = EXTENSION[:version].to_s.freeze
    INFO_UPDATE  = EXTENSION[:update].to_s.freeze
    INFO_START   = EXTENSION[:dev_start].to_s.freeze

    # Copyright range: dev_start year to current year
    year_start   = INFO_START[/\d{4}/]&.to_i || 2023
    year_current = Time.now.year rescue nil
    year_range   =
      if year_current.nil?
        "#{year_start}-Now"
      elsif year_current > year_start
        "#{year_start}-#{year_current}"
      else
        year_start.to_s
      end

    INFO_COPY    = "\u00A9 #{INFO_AUTHOR}, #{year_range}".freeze

  end # module FaceUp
end # module ASM_Extensions
