require 'riddick'

module Riddick
  # Main Riddick GUI.
  # Can be run as a stand-alone app or mounten into another Rails app.
  # All translations cam be changed (see README for further details).
  # To change the templates, subclass Riddick::Server and set change the view path.
  class Server < Sinatra::Base
    # I18n load the fallback translations lazy.
    # To correctly display the default translations, we have to ensure they are loaded on startup.
    Riddick::Backends.simple.init_translations

    def initialize(reject_key_pattern: nil)
      super
      @reject_key_pattern = reject_key_pattern
    end

    # Filter translation keys
    def filter_translations(translations)
      return translations unless @reject_key_pattern.is_a? Regexp
      return translations.reject { |key| key =~ @reject_key_pattern }
    end

    helpers do
      # Build an internal URL.
      def url(*parts)
        [request.script_name, parts].join('/').squeeze '/'
      end

      # Rails-style partial
      def partial(template, *args)
        options = args.extract_options!
        options.merge!(:layout => false)
        if collection = options.delete(:collection) then
          collection.inject([]) do |buffer, member|
            buffer << erb(template, options.merge(
                                      :layout => false,
                                      :locals => {template.to_sym => member}
                                    )
                         )
          end.join("\n")
        else
          erb(template, options)
        end
      end

      # URL for the main interface.
      def root_url
        url '/'
      end

      # URL for displaying default translations only.
      def default_url
        url 'default'
      end

      # URL for displaying custom translations only.
      def my_url
        url 'my'
      end

      # URL for storing a translation.
      def set_url
        url 'set'
      end

      # URL for deleting a translation.
      def del_url(k)
        url('del') + "?k=#{URI.escape k}"
      end

      # Shortcut for namepspaces localization
      def t(path, default = nil)
        I18n.t "riddick.#{path}", default: default
      end

      # Truncate a string with default length 30. Truncation string is '...' by default
      # and can be changed by changing the appropriate translation (see README for further details).
      def truncate(v, l = 30)
        s = v.to_s
        s.size > l ? s.first(l) + t('truncation', '...') : s
      end

      def h(text)
        Rack::Utils.escape_html(text)
      end

      def key_locale(key, locale)
        "#{locale}.#{key_without_locale(key)}"
      end

      def key_without_locale(key)
        key.sub(/^\w+./, "")
      end

      def locales_other_than(locale)
        I18n.available_locales - [:"#{locale}"]
      end

      def flag_emoji(country_code)
        @flag_emoji ||= {
          en: 'GB'.tr('A-Z', "\u{1F1E6}-\u{1F1FF}"),
          id: 'ID'.tr('A-Z', "\u{1F1E6}-\u{1F1FF}")
        }

        return @flag_emoji[:"#{country_code}"]
      end
    end

    # Render index page with all translations.
    get '/' do
      @other_translations = {}
      I18n.available_locales.each do |other_locale|
        I18n.locale = other_locale
        predefined = Riddick::Backends.simple.translations
        custom = Riddick::Backends.key_value.translations
        @other_translations[other_locale] = filter_translations predefined.merge(custom)
      end

      @translations = @other_translations[I18n.default_locale]
      @already_rendered = Set.new
      @option_already_rendered = Set.new

      erb :index
    end

    # Render index page with default translations only.
    get '/default' do
      @other_translations = {}
      I18n.available_locales.each do |other_locale|
        I18n.locale = other_locale
        @other_translations[other_locale] = filter_translations Riddick::Backends.simple.translations
      end

      @translations = @other_translations[I18n.default_locale]
      @already_rendered = Set.new
      @option_already_rendered = Set.new

      erb :index
    end

    # Render index page with custom translations only.
    get '/my' do
      @other_translations = {}
      I18n.available_locales.each do |other_locale|
        I18n.locale = other_locale
        @other_translations[other_locale] = filter_translations Riddick::Backends.key_value.translations
      end

      @translations = @other_translations[I18n.default_locale]
      @already_rendered = Set.new
      @option_already_rendered = Set.new

      erb :index
    end

    # Store a translation.
    # Params (both have to be non-empty values):
    #   k - path for the translation (including the locale).
    #   v - the translation itself.
    post '/set' do
      k, v = params[:k], params[:v]
      if k && v && !k.empty? && !v.empty?
        Riddick::Backends.store_translation k, v
        session[:flash_success] = t('notice.set.success', 'Translation successfully stored!')
      else
        session[:flash_error] = t('notice.set.error', 'Error: either path or translation is empty!')
      end
      redirect my_url
    end

    # Delete a translation.
    # Params (have to be a non-empty value):
    #   k - path for the translation (including the locale).
    get '/del' do
      k = params[:k]
      if k && !k.empty?
        Riddick::Backends.delete_translation k
        session[:flash_success] = t('notice.del.success', 'Translation successfully deleted!')
      else
        session[:flash_error] = t('notice.del.error', 'Error: no such key or key empty!')
      end
      redirect(request.referer || root_url)
    end
  end
end
