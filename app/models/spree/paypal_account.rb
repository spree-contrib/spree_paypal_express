class Spree::PaypalAccount < ActiveRecord::Base
  has_many :payments, :as => :source

  def actions
    %w{capture credit}
  end

  def capture(payment)
    authorization = find_authorization(payment)

    ppx_response = payment.payment_method.provider.capture(amount_in_cents(payment.amount), authorization.params["transaction_id"], :currency => payment.payment_method.preferred_currency)
    if ppx_response.success?
      record_log payment, ppx_response
      payment.complete
    else
      gateway_error(ppx_response.message)
    end

  end

  def can_capture?(payment)
    !echeck?(payment) && payment.state == "pending"
  end

  def credit(payment, amount=nil)
    authorization = find_capture(payment)

    amount = payment.credit_allowed >= payment.order.outstanding_balance.abs ? payment.order.outstanding_balance : payment.credit_allowed

    ppx_response = payment.payment_method.provider.credit(amount.nil? ? amount_in_cents(amount) : amount_in_cents(amount), authorization.params['transaction_id'])

    if ppx_response.success?
      record_log payment, ppx_response
      payment.update_attribute(:amount, payment.amount - amount)
      payment.complete
      payment.order.update!
    else
      gateway_error(ppx_response.message)
    end
  end

  def can_credit?(payment)
    return false unless payment.state == "completed"
    return false unless payment.order.payment_state == "credit_owed"
    payment.credit_allowed > 0
    !find_capture(payment).nil?
  end

  # fix for Payment#payment_profiles_supported?
  def payment_gateway
    false
  end

  def echeck?(payment)
    logs = payment.log_entries.all(:order => 'created_at DESC')
    logs.each do |log|
      details = YAML.load(log.details) # return the transaction details
      if details.params['payment_type'] == 'echeck'
        return true
      end
    end
    return false
  end

  def record_log(payment, response)
    payment.log_entries.create(:details => response.to_yaml)
  end

  private
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

  def gateway_error(text)
    msg = "#{I18n.t('gateway_error')} ... #{text}"
    logger.error(msg)
    raise Spree::Core::GatewayError.new(msg)
  end

  private

    def amount_in_cents(amount)
      (100 * amount).to_i
    end
end
