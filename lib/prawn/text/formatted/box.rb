# encoding: utf-8

# text/formatted/rectangle.rb : Implements text boxes with formatted text
#
# Copyright February 2010, Daniel Nelson. All Rights Reserved.
#
# This is free software. Please see the LICENSE and COPYING files for details.
#

module Prawn
  module Text
    module Formatted

      # Draws the requested formatted text into a box. When the text overflows
      # the rectangle shrink to fit or truncate the text. Text boxes are
      # independent of the document y position.
      #
      # == Formatted Text Array
      #
      # Formatted text is comprised of an array of hashes, where each hash
      # defines text and format information. As of the time of writing, the
      # following hash options are supported:
      #
      # <tt>:text</tt>::
      #     the text to format according to the other hash options
      # <tt>:styles</tt>::
      #     an array of styles to apply to this text. Available styles include
      #     :bold, :italic, :underline, :strikethrough, :subscript, and
      #     :superscript
      # <tt>:size</tt>::
      #     a number denoting the font size to apply to this text
      # <tt>:character_spacing</tt>::
      #     a number denoting how much to increase or decrease the default
      #     spacing between characters
      # <tt>:font</tt>::
      #     the name of a font. The name must be an AFM font with the desired
      #     faces or must be a font that is already registered using
      #     Prawn::Document#font_families
      # <tt>:color</tt>::
      #     anything compatible with Prawn::Graphics::Color#fill_color and
      #     Prawn::Graphics::Color#stroke_color
      # <tt>:link</tt>::
      #     a URL to which to create a link. A clickable link will be created
      #     to that URL. Note that you must explicitly underline and color using
      #     the appropriate tags if you which to draw attention to the link
      # <tt>:anchor</tt>::
      #     a destination that has already been or will be registered using
      #     Prawn::Core::Destinations#add_dest. A clickable link will be
      #     created to that destination. Note that you must explicitly underline
      #     and color using the appropriate tags if you which to draw attention
      #     to the link
      # <tt>:callback</tt>::
      #     an object (or array of such objects) with two methods:
      #     #render_behind and #render_in_front, which are called immediately
      #     prior to and immediately after rendring the text fragment and which
      #     are passed the fragment as an argument
      #
      # == Example
      #
      #   formatted_text_box([{ :text => "hello" },
      #                       { :text => "world",
      #                         :size => 24,
      #                         :styles => [:bold, :italic] }])
      #
      # == Options
      #
      # Accepts the same options as Text::Box with the below exceptions
      #
      # == Returns
      #
      # Returns a formatted text array representing any text that did not print
      # under the current settings.
      #
      # == Exceptions
      #
      # Raises "Bad font family" if no font family is defined for the current font
      #
      # Raises <tt>Prawn::Errrors::CannotFit</tt> if not wide enough to print
      # any text
      #
      def formatted_text_box(array, options={})
        Text::Formatted::Box.new(array, options.merge(:document => self)).render
      end

      # Generally, one would use the Prawn::Text::Formatted#formatted_text_box
      # convenience method. However, using Text::Formatted::Box.new in
      # conjunction with #render(:dry_run => true) enables one to do look-ahead
      # calculations prior to placing text on the page, or to determine how much
      # vertical space was consumed by the printed text
      #
      class Box
        include Prawn::Core::Text::Formatted::Wrap

        def valid_options
          Prawn::Core::Text::VALID_OPTIONS + [:at, :height, :width,
                                              :align, :valign,
                                              :rotate, :rotate_around,
                                              :overflow, :min_font_size,
                                              :leading, :character_spacing,
                                              :mode, :single_line,
                                              :skip_encoding,
                                              :document,
                                              :direction,
                                              :fallback_fonts]
        end

        # The text that was successfully printed (or, if <tt>dry_run</tt> was
        # used, the text that would have been successfully printed)
        attr_reader :text

        # True iff nothing printed (or, if <tt>dry_run</tt> was
        # used, nothing would have been successfully printed)
        def nothing_printed?
          @nothing_printed
        end

        # True iff everything printed (or, if <tt>dry_run</tt> was
        # used, everything would have been successfully printed)
        def everything_printed?
          @everything_printed
        end

        # The upper left corner of the text box
        attr_reader :at
        # The line height of the last line printed
        attr_reader :line_height
        # The height of the ascender of the last line printed
        attr_reader :ascender
        # The height of the descender of the last line printed
        attr_reader :descender
        # The leading used during printing
        attr_reader :leading

        def line_gap
          line_height - (ascender + descender)
        end

        #
        # Example (see Prawn::Text::Core::Formatted::Wrap for what is required
        # of the wrap method if you want to override the default wrapping
        # algorithm):
        # 
        #
        #   module MyWrap
        #
        #     def wrap(array)
        #       initialize_wrap([{ :text => 'all your base are belong to us' }])
        #       @line_wrap.wrap_line(:document => @document,
        #                            :kerning => @kerning,
        #                            :width => 10000,
        #                            :arranger => @arranger)
        #       fragment = @arranger.retrieve_fragment
        #       format_and_draw_fragment(fragment, 0, @line_wrap.width, 0)
        #       []
        #     end
        #
        #   end
        #
        #   Prawn::Text::Formatted::Box.extensions << MyWrap
        #
        #   box = Prawn::Text::Formatted::Box.new('hello world')
        #   box.render('why can't I print anything other than' +
        #              '"all your base are belong to us"?')
        #
        #
        def self.extensions
          @extensions ||= []
        end

        def self.inherited(base) #:nodoc:
          extensions.each { |e| base.extensions << e }
        end

        # See Prawn::Text#text_box for valid options
        #
        def initialize(formatted_text, options={})
          @inked             = false
          Prawn.verify_options(valid_options, options)
          options            = options.dup

          self.class.extensions.reverse_each { |e| extend e }

          @overflow          = options[:overflow] || :truncate

          self.original_text = formatted_text
          @text              = nil

          @document          = options[:document]
          @direction         = options[:direction] || @document.text_direction
          @fallback_fonts    = options[:fallback_fonts] ||
                               @document.fallback_fonts
          @at                = (options[:at] ||
                               [@document.bounds.left, @document.bounds.top]).dup
          @width             = options[:width] ||
                               @document.bounds.right - @at[0]
          @height            = options[:height] || default_height
          @align             = options[:align] ||
                               (@direction == :rtl ? :right : :left)
          @vertical_align    = options[:valign] || :top
          @leading           = options[:leading] || @document.default_leading
          @character_spacing = options[:character_spacing] ||
                               @document.character_spacing
          @mode              = options[:mode] || @document.text_rendering_mode
          @rotate            = options[:rotate] || 0
          @rotate_around     = options[:rotate_around] || :upper_left
          @single_line       = options[:single_line]
          @skip_encoding     = options[:skip_encoding] || @document.skip_encoding

          if @overflow == :expand
            # if set to expand, then we simply set the bottom
            # as the bottom of the document bounds, since that
            # is the maximum we should expand to
            @height = default_height
            @overflow = :truncate
          end
          @min_font_size = options[:min_font_size] || 5
          if options[:kerning].nil? then
            options[:kerning] = @document.default_kerning?
          end
          @options = { :kerning => options[:kerning],
            :size    => options[:size],
            :style   => options[:style] }

          super(formatted_text, options)
        end

        # Render text to the document based on the settings defined in initialize.
        #
        # In order to facilitate look-ahead calculations, <tt>render</tt> accepts
        # a <tt>:dry_run => true</tt> option. If provided, then everything is
        # executed as if rendering, with the exception that nothing is drawn on
        # the page. Useful for look-ahead computations of height, unprinted text,
        # etc.
        #
        # Returns any text that did not print under the current settings
        #
        def render(flags={})
          unprinted_text = []

          @document.save_font do
            @document.character_spacing(@character_spacing) do
              @document.text_rendering_mode(@mode) do
                process_options

                if @skip_encoding
                  text = original_text
                else
                  text = normalize_encoding
                end

                @document.font_size(@font_size) do
                  shrink_to_fit(text) if @overflow == :shrink_to_fit
                  process_vertical_alignment(text)
                  @inked = true unless flags[:dry_run]
                  if @rotate != 0 && @inked
                    unprinted_text = render_rotated(text)
                  else
                    unprinted_text = wrap(text)
                  end
                  @inked = false
                end
              end
            end
          end

          unprinted_text
        end

        # The width available at this point in the box
        #
        def available_width
          @width
        end

        # The height actually used during the previous <tt>render</tt>
        # 
        def height
          return 0 if @baseline_y.nil? || @descender.nil?
          (@baseline_y - @descender).abs
        end

        # <tt>fragment</tt> is a Prawn::Text::Formatted::Fragment object
        #
        def draw_fragment(fragment, accumulated_width=0, line_width=0, word_spacing=0) #:nodoc:
          case(@align)
          when :left
            x = @at[0]
          when :center
            x = @at[0] + @width * 0.5 - line_width * 0.5
          when :right
            x = @at[0] + @width - line_width
          when :justify
            if @direction == :ltr
              x = @at[0]
            else
              x = @at[0] + @width - line_width
            end
          end

          x += accumulated_width

          y = @at[1] + @baseline_y

          y += fragment.y_offset

          fragment.left = x
          fragment.baseline = y

          if @inked
            draw_fragment_underlays(fragment)

            @document.word_spacing(word_spacing) {
              @document.draw_text!(fragment.text, :at => [x, y],
                                   :kerning => @kerning)
            }

            draw_fragment_overlays(fragment)
          end
        end

        private

        def original_text
          @original_array.collect { |hash| hash.dup }
        end

        def original_text=(formatted_text)
          @original_array = formatted_text
        end

        def normalize_encoding
          formatted_text = original_text

          unless @fallback_fonts.empty?
            formatted_text = process_fallback_fonts(formatted_text)
          end

          formatted_text.each do |hash|
            if hash[:font]
              @document.font(hash[:font]) do
                hash[:text] = @document.font.normalize_encoding(hash[:text])
              end
            else
              hash[:text] = @document.font.normalize_encoding(hash[:text])
            end
          end

          formatted_text
        end

        def process_fallback_fonts(formatted_text)
          modified_formatted_text = []

          formatted_text.each do |hash|
            fragments = analyze_glyphs_for_fallback_font_support(hash)
            modified_formatted_text.concat(fragments)
          end

          modified_formatted_text
        end

        def analyze_glyphs_for_fallback_font_support(hash)
          font_glyph_pairs = []

          original_font = @document.font.family
          fragment_font = hash[:font] || original_font
          @document.font(fragment_font)

          fallback_fonts = @fallback_fonts.dup
          # always default back to the current font if the glyph is missing from
          # all fonts
          fallback_fonts << fragment_font

          hash[:text].unpack("U*").each do |char_int|
            char = [char_int].pack("U")
            @document.font(fragment_font)
            font_glyph_pairs << [find_font_for_this_glyph(char,
                                                          @document.font.family,
                                                          fallback_fonts.dup),
                                 char]
          end

          @document.font(original_font)

          form_fragments_from_like_font_glyph_pairs(font_glyph_pairs, hash)
        end

        def find_font_for_this_glyph(char, current_font, fallback_fonts)
          if fallback_fonts.length == 0 || @document.font.glyph_present?(char)
            current_font
          else
            current_font = fallback_fonts.shift
            @document.font(current_font)
            find_font_for_this_glyph(char, @document.font.family, fallback_fonts)
          end
        end

        def form_fragments_from_like_font_glyph_pairs(font_glyph_pairs, hash)
          fragments = []
          fragment = nil
          current_font = nil

          font_glyph_pairs.each do |font, char|
            if font != current_font
              current_font = font
              fragment = hash.dup
              fragment[:text] = char
              fragment[:font] = font
              fragments << fragment
            else
              fragment[:text] += char
            end
          end

          fragments
        end

        def move_baseline_down
          if @baseline_y == 0
            @baseline_y  = -@ascender
          else
            @baseline_y -= (@line_height + @leading)
          end
        end

        # Returns the default height to be used if none is provided or if the
        # overflow option is set to :expand. If we are in a stretchy bounding
        # box, assume we can stretch to the bottom of the innermost non-stretchy
        # box.
        #
        def default_height
          # Find the "frame", the innermost non-stretchy bbox.
          frame = @document.bounds
          frame = frame.parent while frame.stretchy? && frame.parent

          @at[1] + @document.bounds.absolute_bottom - frame.absolute_bottom
        end

        def process_vertical_alignment(text)
          return if @vertical_align == :top
          wrap(text)

          case @vertical_align
          when :center
            @at[1] = @at[1] - (@height - height) * 0.5
          when :bottom
            @at[1] = @at[1] - (@height - height)
          end
          @height = height
        end

        # Decrease the font size until the text fits or the min font
        # size is reached
        def shrink_to_fit(text)
          until @everything_printed || @font_size <= @min_font_size
            @font_size = [@font_size - 0.5, @min_font_size].max
            @document.font_size = @font_size
          end
        end

        def process_options
          # must be performed within a save_font bock because
          # document.process_text_options sets the font
          @document.process_text_options(@options)
          @font_size = @options[:size]
          @kerning   = @options[:kerning]
        end

        def render_rotated(text)
          unprinted_text = ''

          case @rotate_around
          when :center
            x = @at[0] + @width * 0.5
            y = @at[1] - @height * 0.5
          when :upper_right
            x = @at[0] + @width
            y = @at[1]
          when :lower_right
            x = @at[0] + @width
            y = @at[1] - @height
          when :lower_left
            x = @at[0]
            y = @at[1] - @height
          else
            x = @at[0]
            y = @at[1]
          end

          @document.rotate(@rotate, :origin => [x, y]) do
            unprinted_text = wrap(text)
          end
          unprinted_text
        end

        def draw_fragment_underlays(fragment)
          fragment.callback_objects.each do |obj|
            obj.render_behind(fragment) if obj.respond_to?(:render_behind)
          end
        end

        def draw_fragment_overlays(fragment)
          draw_fragment_overlay_styles(fragment)
          draw_fragment_overlay_link(fragment)
          draw_fragment_overlay_anchor(fragment)
          fragment.callback_objects.each do |obj|
            obj.render_in_front(fragment) if obj.respond_to?(:render_in_front)
          end
        end

        def draw_fragment_overlay_link(fragment)
          return unless fragment.link
          box = fragment.absolute_bounding_box
          @document.link_annotation(box,
                                    :Border => [0, 0, 0],
                                    :A => { :Type => :Action,
                                            :S => :URI,
                                            :URI => Prawn::Core::LiteralString.new(fragment.link) })
        end

        def draw_fragment_overlay_anchor(fragment)
          return unless fragment.anchor
          box = fragment.absolute_bounding_box
          @document.link_annotation(box,
                                    :Border => [0, 0, 0],
                                    :Dest => fragment.anchor)
        end

        def draw_fragment_overlay_styles(fragment)
          underline = fragment.styles.include?(:underline)
          if underline
            @document.stroke_line(fragment.underline_points)
          end
          
          strikethrough = fragment.styles.include?(:strikethrough)
          if strikethrough
            @document.stroke_line(fragment.strikethrough_points)
          end
        end

      end

    end
  end
end
