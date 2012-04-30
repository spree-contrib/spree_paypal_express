class Spree::BillingIntegration::PaypalExpress < Spree::BillingIntegration
  preference :login, :string
  preference :password, :password
  preference :signature, :string
  preference :review, :boolean, :default => false
  preference :no_shipping, :boolean, :default => false
  preference :currency, :string, :default => 'USD'
  preference :allow_guest_checkout, :boolean, :default => false

  attr_accessible :preferred_login, :preferred_password, :preferred_signature, :preferred_review, :preferred_no_shipping, :preferred_currency, :preferred_allow_guest_checkout, :preferred_server, :preferred_test_mode

  def provider_class
    ActiveMerchant::Billing::PaypalExpressGateway
  end
end
