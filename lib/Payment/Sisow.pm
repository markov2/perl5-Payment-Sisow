# This code is part of distribution Payment::Sisow.  Meta-POD processed with
# OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Payment::Sisow;

use warnings;
use strict;
use utf8;

use Log::Report 'sisow';

use Digest::SHA1   qw(sha1_hex);

# documentation calls this "alfanumerical characters"
my $valid_purchase_chars = q{ A-Za-z0-9=%*+,./&@"':;?()$-};
my $valid_descr_chars    = q{ A-Za-z0-9=%*+,./&@"':;?()$-};
my $purchase_become_star = q{"':;?()$};    # accepted but replaced by Sisow

# documentation calls this "strict alfanumerical characters"
my $valid_entrance_chars = q{A-Za-z0-9};

=chapter NAME
Payment::Sisow - payments via Sisow

=chapter SYNOPSIS

  my $sisow = Payment::Sisow::SOAP->new(%opts);

  foreach my $bank ($sisow->listIdealBanks)
  {   print "$bank->{id}\t$bank->{name}\n";
  }

  my ($trxid, $redirect) = $sisow->startTransaction(%opts);
  my $status = $sisow->transactionStatus($trxid);
  my $info   = $sisow->transactionInfo($trxid);

=chapter DESCRIPTION
Sisow (F<http://sisow.nl>) is a Dutch payment broker, which offers a
SOAP and a REST interface for communication.  This implementation tries
to offer a common API which will work for both protocols, although currently
only the SOAP version is realized.  The REST interface offers more.

You can test this module using the script in the F<examples/> directory
contained in the CPAN distribution of C<Payment-Sisow>.  It is an
extensive demo.

Please support my development work by submitting bug-reports, patches
and (if available) a donation.

=chapter METHODS

=section Constructors

=c_method new OPTIONS
Inside Sisow's customer website, you can find the generated merchant
B<id> (semi-secret registration number) and B<key> (secret which
is used to sign the replies).

=requires merchant_id STRING
The Sisow customer's unique key.

=requires merchant_key STRING
The "merchants" password.

=option  test BOOLEAN
=default test <false>
You have to enable the permission to run tests in the customer website
of Sisow.  If not enabled, you will get "317" errors.
=cut

sub new(%)
{   my $class = shift;
    $class ne __PACKAGE__ or panic "instantiate an extension of ".__PACKAGE__;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{PS_m_id}  = $args->{merchant_id}  or panic "merchant_id required";
    $self->{PS_m_key} = $args->{merchant_key} or panic "merchant_key required";
    $self->{PS_test}  = $args->{test} || 0;
    $self;
}

#--------------
=section Accessors
=method merchantId
=method merchantKey
=method isTest
=cut

sub merchantId()  {shift->{PS_m_id}}
sub merchantKey() {shift->{PS_m_key}}
sub isTest()      {shift->{PS_test}}

#--------------
=section Calls
=cut

=method listIdealBanks OPTIONS
List the banks which offer iDEAL.  With iDEAL, the webshop lists the
customer banks, which each have their own landing page.  Returned is a
(reference to an) ARRAY of HASHes, each with a bank and id field.

=example
  foreach my $bank ($sisow->listIdealBanks)
  {   print "$bank->{name}\n";
  }
=cut

sub listIdealBanks(%)
{   my ($self, %args) = @_;
    my $b = $self->_list_ideal_banks(%args);
    $b ? @$b : ();
}

=method transactionStatus TRANSACTION_ID
Returns C<undef>, "Open", "Success", "Expired", "Cancelled", "Failure",
"Pending", "Credited", or "Reversed".

=example
  my $status = $sisow->transactionStatus($trxid) || 'MISSING';
  if($status eq 'Expired') ...
=cut

sub transactionStatus($)
{   my ($self, $tid) = @_;

    my $p = $self->_transaction_status
      ( transaction => $tid
      , merchantid  => $self->merchantId
      , merchantkey => $self->merchantKey
      ) or return undef;

    $p->{status};
}


=method transactionInfo TRANSACTION_ID
Returns a HASH with complex information.

=example
   my $info = $sisow->transactionStatus($trxid)
       or die "cannot retrieve info for $trxid\n";
=cut

sub transactionInfo($)
{   my ($self, $tid) = @_;

    my $p = $self->_transaction_info
      ( transaction => $tid
      , merchantid  => $self->merchantId
      , merchantkey => $self->merchantKey
      ) or return undef;

    $p->{stamp} =~ s/ /T/;  # timestamp lacks 'T' between date and time
    $p;
}

=method startTransaction OPTIONS
Returns a transaction id and an url where the user needs to get
redirected to.

=requires purchase_id STRING
=requires amount      FLOAT_EURO

=option  entrance_code STRING
=default entrance_code <undef>

=option  bank_id     ISSUERID
=default bank_id     <undef>
Required when C<payment> is C<ideal>

=option  description  STRING
=default description  <undef>

=option  payment     PROVIDER
=default payment     'ideal'

=requires return_url   URL
Sets the default for all communications from the sisow server to your
application.  It is the user's browser which passes the information on, so
you must return a page to the user as answer.  The parameters returned are
'trxid', 'ec', 'status', and 'sha1'.

=option   cancel_url   URL
=default  cancel_url   <return_url>
Point of return when the transaction is not succesful, for instance
cancelled by the user.

=option   callback_url URL
=default  callback_url <return_url>
Called by sisow when the user has "disappeared", the transaction gets
cancelled.

=option   notify_url   URL
=default  notify_url   <return_url>
Point for any status change in the transaction.

Pick from:

  ideal         iDEAL  (The Netherlands)
  mistercash    BanContact/MisterCash (Belgium)
  sofort        DIRECTebanking (Germany)
  webshop       WebShop GiftCard (The Netherlands)
  podium        Podium Cadeaukaart (The Netherlands)
  ebill         indirect payments

=example

  my ($trxid, $redirect) = try { $sisow->startTransation(%args) };
  die $@->wasFatal if $@;

=cut

sub startTransaction(%)
{   my ($self, %args) = @_;
    my $bank_id     = $args{bank_id};
    my $amount_euro = $args{amount}  // panic;
    my $amount_cent = int($amount_euro*100 + 0.5); # float euro -> int cents

    my $purchase_id = $args{purchase_id} or panic;
    if(length $purchase_id > 16)
    {   # max 16 chars alphanum
        $purchase_id =~ s/[^$valid_purchase_chars]/ /g;
        warning __x"purchase_id shortened: {id}", id => $purchase_id;
        $purchase_id = substr $purchase_id, 0, 16;
    }

    my $description;
    if(my $d = $args{description})
    {   # max 32 alphanumerical. '_' allowed?
        for($d)
        {   s/[^$valid_descr_chars]/ /g;
            s/\s+/ /gs;
            s/\s+$//s;
        }
        if(length $d > 32)
        {   warning __x"description shortened for {id}: {descr}"
              , id => $purchase_id, descr => $d;
        }
        $description = $d;
    }

    my $entrance = $args{entrance_code} || $purchase_id;
    $entrance    =~ s/[^$valid_entrance_chars]//g;
    if(length $entrance > 40)
    {   # max 40 chars, defaults to purchaseid
        warning __x"entrance code shortened for {id}: {code}"
          , id => $purchase_id, code => $entrance;
        $entrance = substr $entrance, 0, 40;
    }
    $entrance    = ''
        if $entrance eq $purchase_id;

    my $payment = $args{payment} || 'ideal';
    error __x"payment via iDEAL requires bank id"
        if $payment eq 'ideal' && !$bank_id;

    my $return   = $args{return_url} or panic;
    my $cancel   = $args{cancel_url};
    my $callback = $args{callback_url};
    my $notify   = $args{notify_url} || $return;
    undef $cancel   if defined $cancel   && $cancel eq $return;
    undef $callback if defined $callback && $callback eq $return;

    my $p        = $self->_start_transaction
      ( merchantid  => $self->merchantId
      , merchantkey => $self->merchantKey
      , payment     => ($payment eq 'ideal' ? '' : $payment)
      , issuerid    => $bank_id
      , amount      => $amount_cent
      , purchaseid  => $purchase_id
      , description => $description
      , entrancecode=> $entrance
      , returnurl   => $return
      , cancelurl   => $cancel
      , callbackurl => $callback
      , notifyurl   => $notify
      ) or return;

    my $bank_page = $p->{issuerurl};
    my $tid       = $p->{trxid};
    info __x"redirecting user for purchase {id} to {url}, transaction {tid}"
      , id => $purchase_id, url => $bank_page, tid => $tid;

    ($tid, $bank_page);
}

#----------------
=section Helpers

=method securedPayment QS|PAIRS
Check whether the payment response was created by Sisow.  QS is a HASH with
the URI parameters, or the same parameters as LIST of PAIRS
=cut

sub securedPayment(@)
{   my $self   = shift;
    my $qs     = @_ > 1 ? {@_} : shift;
    my $ec     = $qs->{ec};
    my $trxid  = $qs->{trxid};
    my $status = $qs->{status};

    # docs say separated by '/', but isn't in practice
    my $checksum = sha1_hex
        (join '', $trxid, $ec, $status, $self->merchantId, $self->merchantKey);

    return 1
        if $checksum eq $qs->{sha1};

    alert "checksum of reply failed: $ec/$trxid/$status sum is $checksum";
    0;
}

=method isValidPurchaseId  STRING
=method isValidDescription STRING
=cut

sub isValidPurchaseId($)  { $_[1] =~ /^[$valid_purchase_chars]{1,16}$/o }
sub isValidDescription($) { $_[1] =~ /^[$valid_descr_chars]{0,32}$/o    }


#--------------
=chapter DETAILS

=section About Sisow

Originally, Sisow focussed on the Dutch cheap and easy iDEAL payment
system --offered by most Dutch banks-- but later it added other types
of payments:

=over 4
=item * ideal; iDEAL for about 12 Dutch banks (NL)
=item * sofort; SofortBanking/DIRECTebanking (DE)
=item * mistercash; Bancontact/MisterCash (BE)
=item * paypalec; PayPal Express Checkout
=item * webshop; Webshop Gift Card (NL)
=item * fijncadeau; Fijn Cadeaukaart (NL)
=item * podium; Podium Cadeaukaart (NL)
=back

Sisow also offers payment services:

=over 4
=item * ecare; pay after delivery
=item * ebill; digital accept giro
=item * overboeking; pay received accept giro
=back

=cut

1;
