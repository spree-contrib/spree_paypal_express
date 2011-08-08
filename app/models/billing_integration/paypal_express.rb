class BillingIntegration::PaypalExpress < BillingIntegration
  preference :login, :string
  preference :password, :password
  preference :signature, :string
  preference :review, :boolean, :default => false
  preference :no_shipping, :boolean, :default => false
  preference :currency, :string, :default => 'USD'

  def provider_class
    ActiveMerchant::Billing::PaypalExpressGateway
  end

end
