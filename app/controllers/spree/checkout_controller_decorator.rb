module Spree
  CheckoutController.class_eval do
    before_filter :redirect_to_paypal_express_form_if_needed, :only => [:update]

    def paypal_checkout
      load_order
      opts = all_opts(@order, params[:payment_method_id], 'checkout')
      opts.merge!(address_options(@order))
      @gateway = paypal_gateway

      if Spree::Config[:auto_capture]
        @ppx_response = @gateway.setup_purchase(opts[:money], opts)
      else
        @ppx_response = @gateway.setup_authorization(opts[:money], opts)
      end

      unless @ppx_response.success?
        gateway_error(@ppx_response)
        redirect_to edit_order_url(@order)
        return
      end

      redirect_to(@gateway.redirect_url_for(response.token, :review => payment_method.preferred_review))
    rescue ActiveMerchant::ConnectionError => e
      gateway_error I18n.t(:unable_to_connect_to_gateway)
      redirect_to :back
    end

    def paypal_payment
      load_order
      opts = all_opts(@order, params[:payment_method_id], 'payment')

      if payment_method.preferred_cart_checkout
        opts.merge!(shipping_options)
      else
        opts.merge!(address_options(@order))
      end

      @gateway = paypal_gateway

      if Spree::Config[:auto_capture]
        @ppx_response = @gateway.setup_purchase(opts[:money], opts)
      else
        @ppx_response = @gateway.setup_authorization(opts[:money], opts)
      end

      unless @ppx_response.success?
        gateway_error(@ppx_response)
        redirect_to edit_order_checkout_url(@order, :state => "payment")
        return
      end

      redirect_to(@gateway.redirect_url_for(@ppx_response.token, :review => payment_method.preferred_review))
    rescue ActiveMerchant::ConnectionError => e
      gateway_error I18n.t(:unable_to_connect_to_gateway)
      redirect_to :back
    end

    def paypal_confirm
      load_order

      opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order, params[:payment_method_id],  'payment')
      gateway = paypal_gateway

      @ppx_details = gateway.details_for params[:token]

      if @ppx_details.success?
        # now save the updated order info

        #TODO Search for existing records

        Spree::PaypalAccount.create(:email => @ppx_details.params["payer"],
                                    :payer_id => @ppx_details.params["payer_id"],
                                    :payer_country => @ppx_details.params["payer_country"],
                                    :payer_status => @ppx_details.params["payer_status"])

        @order.special_instructions = @ppx_details.params["note"]

        unless payment_method.preferred_no_shipping
          ship_address = @ppx_details.address
          order_ship_address = Spree::Address.new :firstname  => @ppx_details.params["first_name"],
                                                  :lastname   => @ppx_details.params["last_name"],
                                                  :address1   => ship_address["address1"],
                                                  :address2   => ship_address["address2"],
                                                  :city       => ship_address["city"],
                                                  :country    => Spree::Country.find_by_iso(ship_address["country"]),
                                                  :zipcode    => ship_address["zip"],
                                                  # phone is currently blanked in AM's PPX response lib
                                                  :phone      => @ppx_details.params["phone"] || "(not given)"

          state = Spree::State.find_by_abbr(ship_address["state"].upcase) if ship_address["state"].present?
          if state
            order_ship_address.state = state
          else
            order_ship_address.state_name = ship_address["state"]
          end
          order_ship_address.save!

          @order.ship_address = order_ship_address
          @order.bill_address ||= order_ship_address

          #Add Instant Update Shipping
          if payment_method.preferred_cart_checkout
            add_shipping_charge
          end

        end
        @order.state = "payment"
        @order.save

        if payment_method.preferred_review

          @order.next
          render 'spree/shared/paypal_express_confirm'
        else
          paypal_finish
        end

      else
        gateway_error(@ppx_details)

        #Failed trying to get payment details from PPX
        redirect_to edit_order_checkout_url(@order, :state => "payment")
      end
    rescue ActiveMerchant::ConnectionError => e
      gateway_error I18n.t(:unable_to_connect_to_gateway)
      redirect_to edit_order_url(@order)
    end

    def paypal_finish
      load_order

      opts = { :token => params[:token], :payer_id => params[:PayerID] }.merge all_opts(@order, params[:payment_method_id], 'payment' )
      gateway = paypal_gateway

      method = Spree::Config[:auto_capture] ? :purchase : :authorize
      ppx_auth_response = gateway.send(method, (@order.total*100).to_i, opts)

      paypal_account = Spree::PaypalAccount.find_by_payer_id(params[:PayerID])

      payment = @order.payments.create(
        :amount => ppx_auth_response.params["gross_amount"].to_f,
        :source => paypal_account,
        :source_type => 'Spree::PaypalAccount',
        :payment_method_id => params[:payment_method_id],
        :response_code => ppx_auth_response.authorization,
        :avs_response => ppx_auth_response.avs_result["code"])

      payment.started_processing!

      record_log payment, ppx_auth_response

      if ppx_auth_response.success?
        #confirm status
        case ppx_auth_response.params["payment_status"]
        when "Completed"
          payment.complete!
        when "Pending"
          payment.pend!
        else
          payment.pend!
          Rails.logger.error "Unexpected response from PayPal Express"
          Rails.logger.error ppx_auth_response.to_yaml
        end

        @order.update_attributes({:state => "complete", :completed_at => Time.now}, :without_protection => true)

        # Unset the order id as it's completed.
        session[:order_id] = nil

        # Since we dont rely on state machine callback, we just explicitly call this method for spree_store_credits
        if @order.respond_to?(:consume_users_credit, true)
          @order.send(:consume_users_credit)
        end

        @order.finalize!
        flash[:notice] = I18n.t(:order_processed_successfully)
        flash[:commerce_tracking] = "true"
        redirect_to completion_route
      else
        payment.failure!
        order_params = {}
        gateway_error(ppx_auth_response)

        #Failed trying to complete pending payment!
        redirect_to edit_order_checkout_url(@order, :state => "payment")
      end
    rescue ActiveMerchant::ConnectionError => e
      gateway_error I18n.t(:unable_to_connect_to_gateway)
      redirect_to edit_order_url(@order)
    end

    private

    def asset_url(_path)
      URI::HTTP.build(:path => ActionController::Base.helpers.asset_path(_path), :host => Spree::Config[:site_url].strip).to_s
    end

    def record_log(payment, response)
      payment.log_entries.create(:details => response.to_yaml)
    end

    def redirect_to_paypal_express_form_if_needed
      return unless (params[:state] == "payment")
      return unless params[:order][:payments_attributes]

      if @order.update_attributes(object_params)
        if params[:order][:coupon_code] and !params[:order][:coupon_code].blank? and @order.coupon_code.present?

          event_name = "spree.checkout.coupon_code_added"
          if promo = Spree::Promotion.with_coupon_code(@order.coupon_code).where(:event_name => event_name).first
            fire_event(event_name, :coupon_code => @order.coupon_code)
          else
            flash[:error] = t(:promotion_not_found)
            render :edit and return
          end

        end
      end

      load_order
      payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])

      if payment_method.kind_of?(Spree::BillingIntegration::PaypalExpress) || payment_method.kind_of?(Spree::BillingIntegration::PaypalExpressUk)
        redirect_to(paypal_payment_order_checkout_url(@order, :payment_method_id => payment_method.id)) and return
      end
    end

    def fixed_opts
      if Spree::PaypalExpress::Config[:paypal_express_local_confirm].nil?
        user_action = "continue"
      else
        user_action = Spree::PaypalExpress::Config[:paypal_express_local_confirm] == "t" ? "continue" : "commit"
      end

      #asset_url doesn't like Spree::Config[:logo] being an absolute url
      #if statement didn't work within hash
      if URI.parse(Spree::Config[:logo]).absolute?
          chosen_image = Spree::Config[:logo]
      else
          chosen_image = asset_url(Spree::Config[:logo])
      end


      { :description             => "Goods from #{Spree::Config[:site_name]}", # site details...
        #:page_style             => "foobar", # merchant account can set named config
        :background_color        => "ffffff",  # must be hex only, six chars
        :header_background_color => "ffffff",
        :header_border_color     => "ffffff",
        :header_image            => chosen_image,
        :allow_note              => true,
        :locale                  => user_locale,
        :req_confirm_shipping    => false,   # for security, might make an option later
        :user_action             => user_action

        # WARNING -- don't use :ship_discount, :insurance_offered, :insurance since
        # they've not been tested and may trigger some paypal bugs, eg not showing order
        # see http://www.pdncommunity.com/t5/PayPal-Developer-Blog/Displaying-Order-Details-in-Express-Checkout/bc-p/92902#C851
      }
    end

    def user_locale
      I18n.locale.to_s
    end

    # hook to override paypal site options
    def paypal_site_opts
      {:currency => payment_method.preferred_currency, :allow_guest_checkout => payment_method.preferred_allow_guest_checkout }
    end

    def order_opts(order, payment_method_id, stage)
      items = order.line_items.map do |item|
        price = (item.price * 100).to_i # convert for gateway
        { :name        => item.variant.product.name.gsub(/<\/?[^>]*>/, ""),
          :description => (item.variant.product.description[0..120].gsub(/<\/?[^>]*>/, "") if item.variant.product.description),
          :number      => item.variant.sku,
          :quantity    => item.quantity,
          :amount      => price,
          :weight      => item.variant.weight,
          :height      => item.variant.height,
          :width       => item.variant.width,
          :depth       => item.variant.weight }
        end

      credits = order.adjustments.eligible.map do |credit|
        if credit.amount < 0.00
          { :name        => credit.label,
            :description => credit.label,
            :sku         => credit.id,
            :quantity    => 1,
            :amount      => (credit.amount*100).to_i }
        end
      end

      credits_total = 0
      credits.compact!
      if credits.present?
        items.concat credits
        credits_total = credits.map {|i| i[:amount] * i[:quantity] }.sum
      end

      if payment_method.preferred_cart_checkout and (order.shipping_method.blank? or order.ship_total == 0)
        shipping_cost  = shipping_options[:shipping_options].first[:amount]
        order_total    = (order.total * 100 + (shipping_cost)).to_i
        shipping_total = (shipping_cost).to_i
      else
        order_total    = (order.total * 100).to_i
        shipping_total = (order.ship_total * 100).to_i
      end

      opts = { :return_url        => paypal_confirm_order_checkout_url(order, :payment_method_id => payment_method_id),
               :cancel_return_url => edit_order_checkout_url(order, :state => :payment),
               :order_id          => order.number,
               :custom            => order.number,
               :items             => items,
               :subtotal          => ((order.item_total * 100) + credits_total).to_i,
               :tax               => (order.tax_total*100).to_i,
               :shipping          => shipping_total,
               :money             => order_total,
               :max_amount        => (order.total * 300).to_i}

      if stage == "checkout"
        opts[:handling] = 0

        opts[:callback_url] = spree.root_url + "paypal_express_callbacks/#{order.number}"
        opts[:callback_timeout] = 3
      elsif stage == "payment"
        #hack to add float rounding difference in as handling fee - prevents PayPal from rejecting orders
        #because the integer totals are different from the float based total. This is temporary and will be
        #removed once Spree's currency values are persisted as integers (normally only 1c)
        if payment_method.preferred_cart_checkout
          opts[:handling] = 0
        else
          opts[:handling] = (order.total*100).to_i - opts.slice(:subtotal, :tax, :shipping).values.sum
        end
      end

      opts
    end

    def shipping_options
      # Uses users address if exists (from spree_address_book or custom implementation), if not uses first shipping method.
      if spree_current_user.present? && spree_current_user.respond_to?(:addresses) && spree_current_user.addresses.present?
        estimate_shipping_for_user
        shipping_default = @rate_hash_user.map.with_index do |shipping_method, idx|
          if @order.shipping_method_id
            default = (@order.shipping_method_id == shipping_method.id)
          else
            default = (idx == 0)
          end
          {
            :default => default,
            :name    => shipping_method.name,
            :amount  => (shipping_method.cost*100).to_i
          }
        end
      else
        shipping_method = @order.shipping_method_id ? ShippingMethod.find(@order.shipping_method_id) : ShippingMethod.all.first
        shipping_default = [{ :default => true,
                              :name => shipping_method.name,
                              :amount => ((shipping_method.calculator.compute(@order).to_f) * 100).to_i }]
      end

      {
        :callback_url      => spree.root_url + "paypal_shipping_update",
        :callback_timeout  => 6,
        :callback_version  => '61.0',
        :shipping_options  => shipping_default
      }
    end

    def address_options(order)
      if payment_method.preferred_no_shipping
        { :no_shipping => true }
      else
        {
          :no_shipping => false,
          :address_override => true,
          :address => {
            :name       => "#{order.ship_address.firstname} #{order.ship_address.lastname}",
            :address1   => order.ship_address.address1,
            :address2   => order.ship_address.address2,
            :city       => order.ship_address.city,
            :state      => order.ship_address.state.nil? ? order.ship_address.state_name.to_s : order.ship_address.state.abbr,
            :country    => order.ship_address.country.iso,
            :zip        => order.ship_address.zipcode,
            :phone      => order.ship_address.phone
          }
        }
      end
    end

    def all_opts(order, payment_method_id, stage=nil)
      opts = fixed_opts.merge(order_opts(order, payment_method_id, stage)).merge(paypal_site_opts)

      if stage == "payment"
        opts.merge! flat_rate_shipping_and_handling_options(order, stage)
      end

      # suggest current user's email or any email stored in the order
      opts[:email] = spree_current_user ? spree_current_user.email : order.email
      if order.bill_address.present?
        opts[:address_override] = 1
        opts[:address] = {
          :name => order.bill_address.full_name,
          :zip => order.bill_address.zipcode,
          :address1 => order.bill_address.address1,
          :address2 => order.bill_address.address2,
          :city => order.bill_address.city,
          :phone => order.bill_address.phone,
          :state => order.bill_address.state_text,
          :country => order.bill_address.country.iso
        }
      end
      opts
    end

    # hook to allow applications to load in their own shipping and handling costs
    def flat_rate_shipping_and_handling_options(order, stage)
      # max_fallback = 0.0
      # shipping_options = ShippingMethod.all.map do |shipping_method|
      #           { :name       => "#{shipping_method.name}",
      #             :amount      => (shipping_method.rate),
      #             :default     => shipping_method.is_default }
      #         end


      # default_shipping_method = ShippingMethod.find(:first, :conditions => {:is_default => true})

      # opts = { :shipping_options  => shipping_options,
      #        }

      # #opts[:shipping] = (default_shipping_method.nil? ? 0 : default_shipping_method.fallback_amount) if stage == "checkout"

      # opts
      {}
    end

    def gateway_error(response)
      if response.is_a? ActiveMerchant::Billing::Response
        text = response.params['message'] ||
               response.params['response_reason_text'] ||
               response.message
      else
        text = response.to_s
      end

      # Parameterize text for i18n key
      text = text.parameterize(sep = '_')
      msg = "#{I18n.t('gateway_error')}: #{I18n.t(text)}"
      logger.error(msg)
      flash[:error] = msg
    end

    # create the gateway from the supplied options
    def payment_method
      @payment_method ||= Spree::PaymentMethod.find(params[:payment_method_id])
    end

    def paypal_gateway
      payment_method.provider
    end

    def add_shipping_charge
      # Replace with these changes once Active_Merchant pushes pending pull request
      # shipment_name = @ppx_details.shipping['amount'].chomp(" Shipping")
      # shipment_cost = @ppx_details.shipping['name'].to_f

      shipment_name = @ppx_details.params['UserSelectedOptions']['ShippingOptionName'].chomp(" Shipping")
      shipment_cost = @ppx_details.params['UserSelectedOptions']['ShippingOptionAmount'].to_f
      if @order.shipping_method_id.blank? && @order.rate_hash.present?
        selected_shipping = @order.rate_hash.detect { |v| v['name'] == shipment_name && v['cost'] == shipment_cost }
        @order.shipping_method_id = selected_shipping.id
      end
      @order.shipments.each { |s| s.destroy unless s.shipping_method.available_to_order?(@order) }
      @order.create_shipment!
      @order.update!
    end

    def estimate_shipping_for_user
      zipcode = spree_current_user.addresses.first.zipcode
      country = spree_current_user.addresses.first.country.iso
      shipping_methods = Spree::ShippingMethod.all
      #TODO remove hard coded shipping
      #Make a deep copy of the order object then stub out the parts required to get a shipping quote
      @shipping_order = Marshal::load(Marshal.dump(@order)) #Make a deep copy of the order object
      @shipping_order.ship_address = Spree::Address.new(:country => Spree::Country.find_by_iso(country), :zipcode => zipcode)
      shipment = Spree::Shipment.new(:address => @shipping_order.ship_address)
      @shipping_order.ship_address.shipments<<shipment
      @shipping_order.shipments<<shipment
      @rate_hash_user = @shipping_order.rate_hash
      #TODO
    end
  end
end
