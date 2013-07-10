use warnings;
use strict;
use utf8;

package Payment::Sisow::SOAP;
use base 'Payment::Sisow';

use Log::Report 'sisow';

use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::SOAP12;  # to understand SOAP1.2 info in WSDL
use XML::Compile::Transport::SOAPHTTP;

use File::Basename qw(dirname);
use File::Spec     ();

my $wsdl_fn = File::Spec->catfile(dirname(__FILE__), 'sisow-soap-v2.0.wsdl');

=chapter NAME
Payment::Sisow::SOAP - payments via the SOAP interface of Sisow

=chapter SYNOPSIS

See M<Payment::Sisow>

=chapter DESCRIPTION
Sisow (F<http://sisow.nl>) is a Dutch payment broker, which offers a SOAP
and a REST interface for communication.  This class extends their
common interface with SOAP specific features.  Oh, the REST interface is
larger...

The full specification of the SOAP interface can be
L<downloaded from Sisow|http://www.sisow.nl/downloads/WebService.pdf>.
However, the REST specification is more clear about the content of
certain fields.

=chapter METHODS

=section Constructors

=c_method new OPTIONS
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $wsdl = $self->{PSS_wsdl} = XML::Compile::WSDL11->new($wsdl_fn);
    $wsdl->compileCalls(port => 'sisowSoap');

    $self;
}

#--------------
=section Accessors
=method wsdl
Returns the XML and SOAP handler object, used internally.  It is a
M<XML::Compile::WSDL11> object.
=cut

sub wsdl()     {shift->{PSS_wsdl}}

#--------------
=section Calls
=cut

sub _list_ideal_banks(%)
{   my ($self, %args) = @_;
    my $test  = (exists $args{test} ? $args{test} : $self->isTest) || 0;
    my ($answer, $trace) = $self->wsdl->call(GetIssuers => test => $test);
    unless($answer)
    {   $trace->printErrors;
        panic $trace->{error};
    }

    # $answer = { parameters =>
    #   { GetIssuersResult => 0,
    #   , issuers => { string => [ 'Sisow Bank (test)', 99 ] }
    #   }};
    my @pairs = @{$answer->{parameters}{issuers}{string} || []};
    my @issuers;
    while(@pairs)
    {   my ($name, $id) = splice @pairs, 0, 2;
        push @issuers, +{name => $name, id => $id};
    }

    \@issuers;
}

sub _transaction_status(%)
{   my ($self, %args) = @_;

    my ($answer, $trace) = $self->wsdl->call(GetStatus => %args);
    unless($answer)
    {   $trace->printErrors;
        panic $trace->{error};
    }

    # $answer = {parameters => {GetStatusResult => 0, status => 'Expired'}};
    my $p  = $answer->{parameters};
    my $rc = $p->{GetStatusResult};
    $rc==0
        or error __x"request transaction {tid} status failed with {rc}"
             , tid => $args{transaction}, rc => $rc;

    $p;
}

sub _transaction_info(%)
{   my ($self, %args) = @_;

    my ($answer, $trace) =  $self->wsdl->call(GetTransaction => %args);
    unless($answer)
    {   $trace->printErrors;
        error $trace->{error};
    }

    # $answer = {parameters => {GetTransactionResult => 0, @pairs}};
    my $p  = $answer->{parameters};
    my $rc = delete $p->{GetTransactionResult};
    $rc==0
        or error __x"request transaction {tid} info failed with {rc}"
             , tid => $args{transation}, rc => $rc;

    $p;
}

sub _start_transaction(%)
{   my ($self, %args) = @_;

    my ($answer, $trace) = $self->wsdl->call(GetURL => %args);
    unless($answer)
    {   $trace->printErrors;
        error $trace->{error};
    }

=for trace

local *TRACE;
if(open TRACE, '>', "/tmp/sisow.$$")
{   use Data::Dumper; $Data::Dumper::Indent =1; $Data::Dumper::Quotekeys=1;
    print TRACE Dumper $answer, $trace;
    close TRACE;
}

=cut

    # $answer = {parameters => {GetURLResult => 0, issuerurl =>, trxid => }};
    my $p  = $answer->{parameters};
    my $rc = delete $p->{GetURLResult};
    $rc==0
        or error __x"start transaction for purchase {id} failed with {rc}"
             , id => $args{purchaseid}, rc => $rc;

    $p;
}

#--------------
=chapter DETAILS

=section errors

Undocumented error codes:   (spec version 1.0)

  317   testing not allowed

=cut

1;
