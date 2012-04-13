Factory.define(:ppx_order) do |record|
  # associations:
  record.association(:user, :factory => :user)
  record.association(:bill_address, :factory => :address)
  record.association(:shipping_method, :factory => :shipping_method)
  record.ship_address { |ship_address| Factory(:ppx_address, :city => "Chevy Chase", :zipcode => "20815") }
end

Factory.define :ppx_order_with_totals, :parent => :order do |f|
  f.after_create { |order| Factory(:line_item, :order => order, :price => 10) and order.line_items.reload }
end
