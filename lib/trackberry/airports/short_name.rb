# frozen_string_literal: true

module Trackberry
  module Airports
    # The compact label for an airport that a person recognises: "London
    # Heathrow", "Lima Jorge Chávez", "Dubai".
    #
    # OurAirports' names are official ("Jorge Chávez International Airport"),
    # and the city is shared by several airports ("London" is five of them). So
    # the label is the name without its generic words, with the city put in
    # front when what is left does not already say it. Built by
    # Trackberry::Airports::Builder into the table's short_name column, so a
    # refresh keeps it current and the reviewed overrides survive it.
    module ShortName
      # Words that say what the place is, not which one it is. Matched whole,
      # without regard to case or accents: "Aéroport" and "Aeroporto" go too.
      GENERIC = %w[
        airport international intl internacional internazionale aeropuerto aeroporto aeroport flughafen
      ].freeze

      module_function

      # +name+ and +city+ as the table holds them. +override+ is a reviewed
      # label (see Builder.short_name_overrides), which wins over the rule.
      def build(name, city, override: nil)
        return override if override

        stripped = strip(name)
        return city || name.to_s.strip if stripped.empty?
        return stripped if city.nil? || fold(stripped).include?(fold(city))

        "#{city} #{stripped}"
      end

      # The name without its generic words and the dashes and slashes left
      # dangling where they stood.
      def strip(name)
        words = name.to_s.split(/\s+/).reject { |word| GENERIC.include?(fold(word)) }
        words.join(" ").gsub(/\A[\s\-–—\/,]+|[\s\-–—\/,]+\z/, "")
      end

      # Lower case without accents, for comparing a name with a city.
      def fold(text)
        text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase
      end
    end
  end
end
