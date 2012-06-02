require 'spec_helper'

feature "paypal express" do
  background do
    PAYMENT_STATES = Spree::Payment.state_machine.states.keys unless defined? PAYMENT_STATES
    SHIPMENT_STATES = Spree::Shipment.state_machine.states.keys unless defined? SHIPMENT_STATES
    ORDER_STATES = Spree::Order.state_machine.states.keys unless defined? ORDER_STATES
    FactoryGirl.create(:shipping_method, :zone => Spree::Zone.find_by_name('North America'))
    FactoryGirl.create(:payment_method, :environment => 'test')
    @product = FactoryGirl.create(:product, :name => "RoR Mug")
    sign_in_as! FactoryGirl.create(:user)

    Factory(:ppx)
  end

  let!(:address) { FactoryGirl.create(:address, :state => Spree::State.first) }

  scenario "can use paypal confirm", :js => true do
    visit spree.product_path(@product)

    click_button "Add To Cart"
    click_link "Checkout"

    str_addr = "bill_address"
    select "United States", :from => "order_#{str_addr}_attributes_country_id"
    ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
      fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
    end

    select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
    check "order_use_billing"
    click_button "Save and Continue"

    pending
    choose "Paypal"
    click_button "Save and Continue"
  end
end