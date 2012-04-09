require File.dirname(__FILE__) + '/../spec_helper'

module Spree
  describe CheckoutController do
    let(:token) { "EC-2OPN7UJGFWK9OYFV" }
    let(:order) { Factory(:ppx_order_with_totals, :state => "payment") }
    let(:order_total) { (order.total * 100).to_i }
    let(:gateway_provider) { mock(ActiveMerchant::Billing::PaypalExpressGateway) }
    let(:paypal_gateway) { mock(BillingIntegration::PaypalExpress, :id => 123, :preferred_review => false, :preferred_no_shipping => true, :provider => gateway_provider, :preferred_currency => "US", :preferred_allow_guest_checkout => true
    ) }

    let(:details_for_response) { mock(ActiveMerchant::Billing::PaypalExpressResponse, :success? => true,
            :params => {"payer" => order.user.email, "payer_id" => "FWRVKNRRZ3WUC"}, :address => {}) }

    let(:purchase_response) { mock(ActiveMerchant::Billing::PaypalExpressResponse, :success? => true,
        :params => {"payer" => order.user.email, "payer_id" => "FWRVKNRRZ3WUC", "gross_amount" => order_total, "payment_status" => "Completed"},
        :avs_result => "F",
        :to_yaml => "fake") }


    before do
      Spree::Auth::Config.set(:registration_step => false)
      controller.stub(:current_order => order, :check_authorization => true, :current_user => order.user)
      order.stub(:checkout_allowed? => true, :completed? => false)
      order.update!
    end

    it "should understand paypal routes" do
      pending("Unknown how to make this work within the scope of an engine again")

      assert_routing("/orders/#{order.number}/checkout/paypal_payment", {:controller => "checkout", :action => "paypal_payment", :order_id => order.number })
      assert_routing("/orders/#{order.number}/checkout/paypal_confirm", {:controller => "checkout", :action => "paypal_confirm", :order_id => order.number })
    end

    context "paypal_checkout" do
      #feature not implemented
    end

    context "paypal_payment without auto_capture" do
      let(:redirect_url) { "https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=#{token}&useraction=commit" }

      before { Spree::Config.set(:auto_capture => false) }

      it "should setup an authorize transaction and redirect to sandbox" do
        PaymentMethod.should_receive(:find).at_least(1).with('123').and_return(paypal_gateway)

        gateway_provider.should_receive(:redirect_url_for).with(token, {:review => false}).and_return redirect_url
        paypal_gateway.provider.should_receive(:setup_authorization).with(order_total, anything()).and_return(mock(:success? => true, :token => token))

        get :paypal_payment, {:order_id => order.number, :payment_method_id => "123" }

        response.should redirect_to "https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=#{assigns[:ppx_response].token}&useraction=commit"
      end

    end

    context "paypal_payment with auto_capture" do
      let(:redirect_url) { "https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=#{token}&useraction=commit" }

      before { Spree::Config.set(:auto_capture => true) }

      it "should setup a purchase transaction and redirect to sandbox" do
        PaymentMethod.should_receive(:find).at_least(1).with("123").and_return(paypal_gateway)

        gateway_provider.should_receive(:redirect_url_for).with(token, {:review => false}).and_return redirect_url
        paypal_gateway.provider.should_receive(:setup_purchase).with(order_total, anything()).and_return(mock(:success? => true, :token => token))

        get :paypal_payment, {:order_id => order.number, :payment_method_id => "123" }

        response.should redirect_to "https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=#{assigns[:ppx_response].token}&useraction=commit"
      end

    end

    context "paypal_confirm" do
      before { PaymentMethod.should_receive(:find).at_least(1).with("123").and_return(paypal_gateway) }

      context "with auto_capture and no review" do
        before do
          Spree::Config.set(:auto_capture => true)
          paypal_gateway.stub(:preferred_review => false)
        end

        it "should capture payment" do
          paypal_gateway.provider.should_receive(:details_for).with(token).and_return(details_for_response)

          paypal_gateway.provider.should_receive(:purchase).with(order_total, anything()).and_return(purchase_response)

          get :paypal_confirm, {:order_id => order.number, :payment_method_id => "123", :token => token, :PayerID => "FWRVKNRRZ3WUC" }

          response.should redirect_to spree.order_path(order)

          order.reload
          order.state.should == "complete"
          order.payments.size.should == 1
          order.payment_state.should == "paid"
        end
      end

      context "with review" do
        before { paypal_gateway.stub(:preferred_review => true) }

        it "should render review" do
          paypal_gateway.provider.should_receive(:details_for).with(token).and_return(details_for_response)

          get :paypal_confirm, {:order_id => order.number, :payment_method_id => "123", :token => token, :PayerID => "FWRVKNRRZ3WUC" }

          response.should render_template("shared/paypal_express_confirm")

        end
      end

      context "with review and shipping update" do
        before do
          paypal_gateway.stub(:preferred_review => true)
          paypal_gateway.stub(:preferred_no_shipping => false)

          details_for_response.stub(:params => details_for_response.params.merge({'first_name' => 'Dr.', 'last_name' => 'Evil'}),
            :address => {'address1' => 'Apt. 187', 'address2'=> 'Some Str.', 'city' => 'Chevy Chase', 'country' => 'US', 'zip' => '20815', 'state' => 'MD' })

        end

        it "should update ship_address and render review" do
          paypal_gateway.provider.should_receive(:details_for).with(token).and_return(details_for_response)

          get :paypal_confirm, {:order_id => order.number, :payment_method_id => "123", :token => token, :PayerID => "FWRVKNRRZ3WUC" }

          order.ship_address.address1.should == "Apt. 187"
          response.should render_template("shared/paypal_express_confirm")
        end
      end

      context "with un-successful repsonse" do
        before { details_for_response.stub(:success? => false) }

        it "should log error and redirect to payment step" do
          paypal_gateway.provider.should_receive(:details_for).with(token).and_return(details_for_response)

          controller.should_receive(:gateway_error).with(details_for_response)

          get :paypal_confirm, {:order_id => order.number, :payment_method_id => "123", :token => token, :PayerID => "FWRVKNRRZ3WUC" }

          response.should redirect_to spree.edit_order_checkout_path(order, :state => 'payment')
        end
      end

    end

    context "paypal_finish" do
      let(:paypal_account) { stub_model(PaypalAccount, :payer_id => "FWRVKNRRZ3WUC", :email => order.email ) }
      let(:authorize_response) { mock(ActiveMerchant::Billing::PaypalExpressResponse, :success? => true,
            :params => {"payer" => order.user.email, "payer_id" => "FWRVKNRRZ3WUC", "gross_amount" => order_total, "payment_status" => "Pending"},
            :avs_result => "F",
            :to_yaml => "fake") }

      before do
        PaymentMethod.should_receive(:find).at_least(1).with("123").and_return(paypal_gateway)
        PaypalAccount.should_receive(:find_by_payer_id).with("FWRVKNRRZ3WUC").and_return(paypal_account)
      end

      context "with auto_capture" do
        before { Spree::Config.set(:auto_capture => true) }

        it "should capture payment" do

          paypal_gateway.provider.should_receive(:purchase).with(order_total, anything()).and_return(purchase_response)

          get :paypal_finish, {:order_id => order.number, :payment_method_id => "123", :token => token, :PayerID => "FWRVKNRRZ3WUC" }

          response.should redirect_to spree.order_path(order)

          order.reload
          order.update!
          order.payments.size.should == 1
          order.payment_state.should == "paid"
        end
      end

      context "with auto_capture and pending(echeck) response" do
        before do
          Spree::Config.set(:auto_capture => true)
          purchase_response.params["payment_status"] = "pending"
        end

        it "should authorize payment" do

          paypal_gateway.provider.should_receive(:purchase).with(order_total, anything()).and_return(purchase_response)

          get :paypal_finish, {:order_id => order.number, :payment_method_id => "123", :token => token, :PayerID => "FWRVKNRRZ3WUC" }

          response.should redirect_to spree.order_path(order)

          order.reload
          order.update!
          order.payments.size.should == 1
          order.payment_state.should == "balance_due"
          order.payment.state.should == "pending"
        end
      end

      context "without auto_capture" do
        before { Spree::Config.set(:auto_capture => false) }

        it "should authorize payment" do

          paypal_gateway.provider.should_receive(:authorize).with(order_total, anything()).and_return(authorize_response)

          get :paypal_finish, {:order_id => order.number, :payment_method_id => "123", :token => token, :PayerID => "FWRVKNRRZ3WUC" }

          response.should redirect_to spree.order_path(order)

          order.reload
          order.update!
          order.payments.size.should == 1
          order.payment_state.should == "balance_due"
          order.payment.state.should == "pending"
        end
      end

      context "with un-successful repsonse" do
        before do
          Spree::Config.set(:auto_capture => true)
          purchase_response.stub(:success? => false)
        end

        it "should log error and redirect to payment step" do
          paypal_gateway.provider.should_receive(:purchase).with(order_total, anything()).and_return(purchase_response)

          controller.should_receive(:gateway_error).with(purchase_response)

          get :paypal_finish, {:order_id => order.number, :payment_method_id => "123", :token => token, :PayerID => "FWRVKNRRZ3WUC" }

          response.should redirect_to spree.edit_order_checkout_path(order, :state => 'payment')

          order.reload
          order.update!
          order.payments.size.should == 1
          order.payment_state.should == "failed"
          order.payment.state.should == "failed"
        end
      end

    end

    context "#fixed_opts" do

      it "returns hash containing basic settings" do
        I18n.locale = :fr
        opts = controller.send(:fixed_opts)
        opts[:header_image].should == "http://demo.spreecommerce.com/assets/admin/bg/spree_50.png"
        opts[:locale].should == "fr"
      end

    end

    context "order_opts" do

      it "should return hash containing basic order details" do
        opts = controller.send(:order_opts, order, paypal_gateway.id, 'payment')

        opts.class.should == Hash
        opts[:money].should == order_total
        opts[:subtotal].should == (order.item_total * 100).to_i
        opts[:order_id].should == order.number
        opts[:custom].should == order.number
        opts[:handling].should == 0
        opts[:shipping].should == (order.ship_total * 100).to_i

        opts[:return_url].should == spree.paypal_confirm_order_checkout_url(order, :payment_method_id => paypal_gateway.id, :host => "test.host")
        opts[:cancel_return_url].should == spree.edit_order_checkout_url(order, :state => 'payment', :host => "test.host")

        opts[:items].size.should > 0
        opts[:items].size.should == order.line_items.count
      end

      it "should include credits in returned hash" do
        order_total #need here so variable is set before credit is created.
        order.adjustments.create(:label => "Credit", :amount => -1)
        order.update!

        opts = controller.send(:order_opts, order, paypal_gateway.id, 'payment')

        opts.class.should == Hash
        opts[:money].should == order_total - 100
        opts[:subtotal].should == ((order.item_total * 100) + (order.adjustments.select{|c| c.amount < 0}.sum(&:amount) * 100)).to_i

        opts[:items].size.should == order.line_items.count + 1
      end


    end

    describe "#paypal_site_opts" do
      it "returns opts to allow guest checkout" do
        controller.should_receive(:payment_method).at_least(1).and_return(paypal_gateway)

        opts = controller.send(:paypal_site_opts)
        opts[:allow_guest_checkout].should be_true
      end
    end
  end
end