require 'spec_helper'

describe Spree::BillingIntegration::PaypalExpressBase do
  let(:order) do
    order = Spree::Order.new(:bill_address => Spree::Address.new,
                             :ship_address => Spree::Address.new)
  end

  let(:gateway) do
    gateway = Spree::BillingIntegration::PaypalExpressBase.new({:environment => 'test', :active => true, :preferred_currency => "EUR"}, :without_protection => true)
    gateway.stub :source_required => true
    gateway.stub :provider => mock('paypal provider')
    gateway.stub :find_authorization => mock('authorization', :params => authorization_params)
    gateway
  end

  let(:authorization_params) { {'transaction_id' => '123'} }
  let(:provider) { gateway.provider }

  let(:account) do
    mock_model(Spree::PaypalAccount)
  end

  let(:payment) do
    payment = Spree::Payment.new
    payment.source = account
    payment.order = order
    payment.payment_method = gateway
    payment.amount = 10.0
    payment
  end

  let(:amount_in_cents) { payment.amount.to_f * 100 }

  let!(:success_response) do
    mock('success_response', :success? => true,
                             :authorization => '123',
                             :avs_result => { 'code' => 'avs-code' })
  end

  let(:failed_response) { mock('gateway_response', :success? => false) }

  before(:each) do
    # So it doesn't create log entries every time a processing method is called
    payment.log_entries.stub(:create)
  end

  describe "#capture" do
    before { payment.state = 'pending' }

    context "when payment_profiles_supported = true" do
      before { gateway.stub :payment_profiles_supported? => true }

       context "if sucessful" do
         before do
           provider.should_receive(:capture).with(amount_in_cents, '123', :currency => 'EUR').and_return(success_response)
         end

         it "should store the response_code" do
           payment.capture!
           payment.response_code.should == '123'
         end
       end

       context "if unsucessful" do
         before do
           gateway.should_receive(:capture).with(payment, account, anything).and_return(failed_response)
         end

         it "should not make payment complete" do
           lambda { payment.capture! }.should raise_error(Spree::Core::GatewayError)
           payment.state.should == "failed"
         end
       end
     end

     context "when payment_profiles_supported = false" do
       before do
         payment.stub :response_code => '123'
         gateway.stub :payment_profiles_supported? => false
       end

       context "if sucessful" do
         before do
           provider.should_receive(:capture).with(amount_in_cents, '123', anything).and_return(success_response)
         end

         it "should store the response_code" do
           payment.capture!
           payment.response_code.should == '123'
         end
       end

       context "if unsucessful" do
         before do
           provider.should_receive(:capture).with(amount_in_cents, '123', anything).and_return(failed_response)
         end

         it "should not make payment complete" do
           lambda { payment.capture! }.should raise_error(Spree::Core::GatewayError)
           payment.state.should == "failed"
         end
       end

     end
  end

  describe "#credit" do
    before { payment.stub :response_code => '123' }
    context "when payment_profiles_supported = true" do
      before { gateway.stub :payment_profiles_supported? => true }


      it "should receive correct params" do
        provider.should_receive(:credit).with(1000, '123', :currency => 'EUR').and_return(success_response)
        payment.credit!(10.0)
        payment.response_code.should == '123'
      end
    end

    context "when payment_profiles_supported = false" do
      before do
        payment.stub :response_code => '123'
        gateway.stub :payment_profiles_supported? => false
      end

      it "should receive correct params" do
        provider.should_receive(:credit).with(amount_in_cents, '123', :currency => 'EUR').and_return(success_response)
        payment.credit!(10.0)
        payment.response_code.should == '123'
      end

    end
  end
end
