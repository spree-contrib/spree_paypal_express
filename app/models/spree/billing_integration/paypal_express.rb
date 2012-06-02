class Spree::BillingIntegration::PaypalExpress < Spree::BillingIntegration::PaypalExpressBase
  preference :currency, :string, :default => 'USD'
end
