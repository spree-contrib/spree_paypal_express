# Official PayPal Express for Spree

This is the official PayPal Express extension for Spree, based on the extension by PaulCC it has been extended to support Spree's
Billing Integrations which allows users to configure the PayPal Express gateway including API login / password and signatures fields
via the Admin UI.

This extension allows the store to use PayPal Express from two locations:

  1. Checkout Payment - When configured the PayPal Express checkout button will appear alongside the standard credit card payment
  options on the payment stage of the standard checkout. The selected shipping address and shipping method / costs are automatically
  sent to the PayPal review page (along with detailed order information).

  
  2. Cart Checkout (THIS FEATURE IS NOT YET COMPLETE) - Presents the PayPal checkout button on the users Cart page and redirects the user to complete
  all shipping / addressing information on PaypPal's site. This also supports PayPal's Instant Update feature to retrieve shipping options live from 
  Spree when the user selects / changes their shipping address on PayPal's site.

This extension follows the documented flow for a PayPal Express Checkout, where a user is forwarded to PayPal to allow them to login and review
the order (possibly select / change shipping address and method), then the user is redirected back to Spree to confirm the order. The user
MUST confirm the order on the Spree site before the payment is authorized / captured from PayPal (and the order is transitioned to the New state).


Versions
========

NOTE: The master branch of this repo is currently unstable due to changes in Spree itself and is being actively worked on.

To determine the correct version of this extension, please refer to the Versionfile.


The legacy 0.11.x version of this extension is available in the [0-11-x](https://github.com/spree/spree_paypal_express/tree/0-11-x) branch.


IPN & eCheck Support
===================
eCheck payments are now fully supported and PayPal's Instant Payment Notification service is also supported for receiving updates relating to eCheck payments only. To configure eCheck payments you'll need to:

###1. Install & Configure the extension (see Installation and Configuration sections below).

###2. Configure your PayPal account to accept eCheck payments (under Profile on PayPal's website).

###3. Set the IPN URL on your PayPal account (under Profile on PayPal's website) to:

     https://www.yourstore.com/paypal_notify

###4. Enable auto_capture within Spree (as eCheck payments are only supported for purchase and not authorize requests).

     Spree::Config.set(:auto_capture => true)


Installation
============

###1. Add the following line to your application's Gemfile

     gem "spree_paypal_express", :git => "git://github.com/spree/spree_paypal_express.git"

**Note:** The :git option is only required for the edge version, and can be removed to used the released gem.

###2. Run bundler

      bundle install

###3. Copy assets / migrations

      rake spree_paypal_express:install

###4. Run migration

      rake db:migrate


Configuration
=============
###1. Before you begin
  
You'll need to have a Paypal developer account (developer.paypal.com) and both buyer and seller test accounts.
  
**Tip:** these are sandbox only, so use email addresses and passwords that are easy to  remember, e.g. buyer@example.com and seller@example.com.
  
Your sandbox credentials are available from the API Credentials link.

###2. Setup the Payment Method
  
Log in as an admin and add a new **Payment Method** (under Configuration), using following details:

**Name:** Paypal Express
  
**Environment:** Development (or what ever environment you prefer)
  
**Active:** Yes
  
**Provider:** BillingIntegration::PaypalExpress
  
Click **Create* , and now add your credentials in the screen that follows:
  
**Review:** unchecked [1]
  
**Signature:** API signature from your paypal seller test account
  
**Server:** test (for Development or live for Production)
  
**Test Mode:** checked (or unchecked for Production)
  
**Password:** API Password from your paypal seller test account
  
**Login:** API Username from your paypal seller test account (care to use the API Username and not the Test Account address)
  
Click **Update**

Test Drive
==========

While testing PayPal Express checkout locally make sure you're logged into your PayPal **developer** account in another browser window before attempting a PayPal payment, as you'll be redirected and forced to sign in to your developer account.

1. Add an item to cart
  
2. Check out
  
3. Address step: complete it using a valid US address.
  
4. Delivery step: pick anything
  
5. On the Payment Step, you should see a PayPal button. You can select it directly or just click "Continue"
  
6. You will get redirected to PayPals sandbox site, be sure to log in as a **Buyer** / **Personal** test account and not the account you use to configure the Payment Method with. 
  
7. You should now see the paypal order details screen with a Pay Now button.
  
8. Click Pay Now, and you should now be redirected back to Spree's order thank you page.
  
9. Log into the Admin UI and review the Order and Payment details to confirm the successful checkout.


Running Specs
=============

###1. Create Test App

    rake test_app

###2. Run Specs

    rake spec

NOTES
=====
    
To automatically capture funds or enable accepting eCheck payments, add this to you site extension's activate method:

    if Spree::Config.instance
      Spree::Config.set(:auto_capture => true)
    end
    
[1] If you check the review checkbox in the admin section for Payment Methods/Paypal Express, the flow is slightly different. Instead of Pay Now on Paypal's order details page, it now says Continue. And the user is directed back to the spree app's Confirmation page showing a place order button. Use whichever suits your needs best. Personally, I leave review unchecked to cut down on the steps in the checkout flow.
