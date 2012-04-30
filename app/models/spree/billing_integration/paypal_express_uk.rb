class Spree::BillingIntegration::PaypalExpressUk < Spree::BillingIntegration
  preference :login, :string
  preference :password, :password
  preference :signature, :string
  preference :review, :boolean, :default => false
  preference :no_shipping, :boolean, :default => false

  attr_accessible :preferred_login, :preferred_password, :preferred_signature, :preferred_review, :preferred_no_shipping, :preferred_server, :preferred_test_mode

  def provider_class
    ActiveMerchant::Billing::PaypalExpressUkGateway
  end

end
