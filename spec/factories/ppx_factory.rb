FactoryGirl.define do
  factory :ppx, :class => Spree::BillingIntegration::PaypalExpress, :parent => :payment_method do
    name 'Paypal'
  end
end