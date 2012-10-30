class Spree::BillingIntegration::PaypalExpressBase < Spree::BillingIntegration
  preference :login, :string
  preference :password, :password
  preference :signature, :string
  preference :review, :boolean, :default => false
  preference :no_shipping, :boolean, :default => false
  preference :cart_checkout, :boolean, :default => false
  preference :currency, :string, :default => 'USD'
  preference :allow_guest_checkout, :boolean, :default => false

  attr_accessible :preferred_login, :preferred_password, :preferred_signature, :preferred_review, :preferred_no_shipping, :preferred_currency, :preferred_allow_guest_checkout, :preferred_server, :preferred_test_mode, :preferred_cart_checkout

  def provider_class
    ActiveMerchant::Billing::PaypalExpressGateway
  end

  def payment_profiles_supported?
    !!preferred_review
  end

  def capture(payment_or_amount, account_or_response_code, gateway_options)
    if payment_or_amount.is_a?(Spree::Payment)
      authorization = find_authorization(payment_or_amount)
      provider.capture(amount_in_cents(payment_or_amount.amount), authorization.params["transaction_id"], :currency => preferred_currency)
    else
      provider.capture(payment_or_amount, account_or_response_code, :currency => preferred_currency)
    end
  end

  def credit(*args)
    amount = args.shift
    response_code = args.first.is_a?(String) ? args.first : args[1]
    provider.credit(amount, response_code, :currency => preferred_currency)
  end

  def find_authorization(payment)
    logs = payment.log_entries.all(:order => 'created_at DESC')
    logs.each do |log|
      details = YAML.load(log.details) # return the transaction details
      if (details.params['payment_status'] == 'Pending' && details.params['pending_reason'] == 'authorization')
        return details
      end
    end
    return nil
  end

  def find_capture(payment)
    #find the transaction associated with the original authorization/capture
    logs = payment.log_entries.all(:order => 'created_at DESC')
    logs.each do |log|
      details = YAML.load(log.details) # return the transaction details
      if details.params['payment_status'] == 'Completed'
        return details
      end
    end
    return nil
  end

  def amount_in_cents(amount)
    (100 * amount).to_i
  end

end