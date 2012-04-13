module Spree
  class PaypalExpressCallbacksController < Spree::BaseController
    include ActiveMerchant::Billing::Integrations
    skip_before_filter :verify_authenticity_token

    ssl_required

    def notify
      retrieve_details #need to retreive details first to ensure ActiveMerchant gets configured correctly.


      @notification = Paypal::Notification.new(request.raw_post)

      # we only care about eChecks (for now?)
      if @notification.params["payment_type"] == "echeck" && @notification.acknowledge && @payment && @order.total >= @payment.amount
        @payment.started_processing!
        @payment.log_entries.create(:details => @notification.to_yaml)

        case @notification.params["payment_status"]
          when "Denied"
            @payment.failure!

          when "Completed"
            @payment.complete!
        end

      end

      render :nothing => true
    end

    private
      def retrieve_details
        @order = Spree::Order.find_by_number(params["invoice"])

        if @order
          @payment = @order.payments.where(:state => "pending", :source_type => "PaypalAccount").try(:first)

          @payment.try(:payment_method).try(:provider) #configures ActiveMerchant
        end
      end

  end
end
