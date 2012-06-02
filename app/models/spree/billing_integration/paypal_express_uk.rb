class Spree::BillingIntegration::PaypalExpressUk < Spree::BillingIntegration::PaypalExpressBase
  preference :currency, :string, :default => 'GBP'
end
