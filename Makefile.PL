#!/usr/bin/env perl
use ExtUtils::MakeMaker;

use 5.010;

my $version = '0.14';

WriteMakefile
 ( NAME	 	=> 'Payment::Sisow'
 , VERSION	=> $version
 , PREREQ_PM    =>
    { Test::More           => 0.80
    , Log::Report          => '1.00'
    , XML::Compile::SOAP11 => '3.00'
    , XML::Compile::SOAP12 => '3.00'
    , XML::Compile::WSDL11 => '3.00'
    , File::Basename       => 0
    , File::Spec           => 0
    , Digest::SHA1         => 0
    , LWP::Protocol::https => 0
    }
 , EXE_FILES    => []
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'connect to Dutch payment broker Sisow'
 , LICENSE      => 'perl_5'

  , META_MERGE =>
      { 'meta-spec' => { version => 2 }
      , resources  =>
          { repository =>
              { type => 'git'
              , url  => 'https://github.com/markov2/perl5-Payment-Sisow.git'
              , web  => 'https://github.com/markov2/perl5-Payment-Sisow'
              }
          , homepage => 'http://perl.overmeer.net/CPAN/'
          , license  => [ 'http://dev.perl.org/licenses/' ]
          }
      }
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/payment-sisow/raw
DISTDIR         = ../public_html/payment-sisow/source
LICENSE         = perl

# for POD
FIRST_YEAR      = 2013
EMAIL           = markov@cpan.org
WEBSITE         = http://perl.overmeer.net/CPAN/
__POSTAMBLE
