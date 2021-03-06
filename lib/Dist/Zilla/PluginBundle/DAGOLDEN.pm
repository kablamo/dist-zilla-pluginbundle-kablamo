use strict;
use warnings;
package Dist::Zilla::PluginBundle::DAGOLDEN;
# VERSION

# Dependencies
use autodie 2.00;
use Moose 0.99;
use Moose::Autobox;
use namespace::autoclean 0.09;

use Dist::Zilla 4.3; # authordeps

use Dist::Zilla::PluginBundle::Filter ();
use Dist::Zilla::PluginBundle::Git 1.121010 ();

use Dist::Zilla::Plugin::AutoMetaResources ();
use Dist::Zilla::Plugin::CheckChangesHasContent ();
use Dist::Zilla::Plugin::CheckExtraTests ();
use Dist::Zilla::Plugin::CheckMetaResources 0.001 ();
use Dist::Zilla::Plugin::CheckPrereqsIndexed 0.002 ();
use Dist::Zilla::Plugin::CopyFilesFromBuild ();
use Dist::Zilla::Plugin::Git::NextVersion ();
use Dist::Zilla::Plugin::InsertCopyright 0.001 ();
use Dist::Zilla::Plugin::MetaNoIndex ();
use Dist::Zilla::Plugin::MetaProvides::Package 1.14 (); # hides DB/main/private packages
use Dist::Zilla::Plugin::MinimumPerl ();
use Dist::Zilla::Plugin::OurPkgVersion 0.004 (); # TRIAL comment support
use Dist::Zilla::Plugin::PodWeaver ();
use Dist::Zilla::Plugin::ReadmeAnyFromPod 0.120051 ();
use Dist::Zilla::Plugin::ReadmeFromPod ();
use Dist::Zilla::Plugin::TaskWeaver 0.101620 ();
use Dist::Zilla::Plugin::Test::Compile ();
use Dist::Zilla::Plugin::Test::Perl::Critic ();
use Dist::Zilla::Plugin::Test::PodSpelling 2.001002 ();
use Test::Portability::Files 0.06 (); # buggy before that
use Dist::Zilla::Plugin::Test::Portability ();
use Dist::Zilla::Plugin::Test::Version ();

with 'Dist::Zilla::Role::PluginBundle::Easy';
with 'Dist::Zilla::Role::PluginBundle::Config::Slicer';

sub mvp_multivalue_args { qw/stopwords/ }

has stopwords => (
  is      => 'ro',
  isa     => 'ArrayRef',
  lazy    => 1,
  default => sub {
    exists $_[0]->payload->{stopwords} ? $_[0]->payload->{stopwords} : []
  },
);

has fake_release => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{fake_release} },
);

has no_critic => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub {
    exists $_[0]->payload->{no_critic} ? $_[0]->payload->{no_critic} : 0
  },
);

has no_spellcheck => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub {
    exists $_[0]->payload->{no_spellcheck}
         ? $_[0]->payload->{no_spellcheck}
         : 0
  },
);

has no_coverage => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub {
    exists $_[0]->payload->{no_coverage}
         ? $_[0]->payload->{no_coverage}
         : 0
  },
);

has is_task => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub { $_[0]->payload->{is_task} },
);

has auto_prereq => (
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => sub {
    exists $_[0]->payload->{auto_prereq} ? $_[0]->payload->{auto_prereq} : 1
  },
);

has tag_format => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {
    exists $_[0]->payload->{tag_format} ? $_[0]->payload->{tag_format} : 'release-%v',
  },
);

has version_regexp => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {
    exists $_[0]->payload->{version_regexp} ? $_[0]->payload->{version_regexp} : '^release-(.+)$',
  },
);

has weaver_config => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub { $_[0]->payload->{weaver_config} || '@DAGOLDEN' },
);

has git_remote => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub {
    exists $_[0]->payload->{git_remote} ? $_[0]->payload->{git_remote} : 'origin',
  },
);

has no_bugtracker => ( # XXX deprecated
  is      => 'ro',
  isa     => 'Bool',
  lazy    => 1,
  default => 0,
);

sub configure {
  my $self = shift;

  my @push_to = ('origin');
  push @push_to, $self->git_remote if $self->git_remote ne 'origin';

  $self->add_plugins (

  # version number
    [ 'Git::NextVersion' => { version_regexp => $self->version_regexp } ],

  # gather and prune
    [ 'Git::GatherDir' => { exclude_filename => [qw/README.pod META.json/] }], # core
    'PruneCruft',         # core
    'ManifestSkip',       # core

  # file munging
    'OurPkgVersion',
    'InsertCopyright',
    ( $self->is_task
      ?  'TaskWeaver'
      : [ 'PodWeaver' => { config_plugin => $self->weaver_config } ]
    ),

  # generated distribution files
    'ReadmeFromPod',
    'License',            # core
    [ ReadmeAnyFromPod => { # generate in root for github, etc.
        type => 'pod',
        filename => 'README.pod',
        location => 'root',
      }
    ],

  # generated t/ tests
    [ 'Test::Compile' => { fake_home => 1 } ],

  # generated xt/ tests
    ( $self->no_spellcheck
        ? ()
        : [ 'Test::PodSpelling' => { stopwords => $self->stopwords } ] ),
    'Test::Perl::Critic',
    'MetaTests',          # core
    'PodSyntaxTests',     # core
    ( $self->no_coverage
        ? ()
        : ('PodCoverageTests') # core
    ),
    [ 'Test::Portability' => { options => "test_one_dot = 0" } ],
    'Test::Version',

  # metadata
    'MinimumPerl',
    ( $self->auto_prereq
      ? [ 'AutoPrereqs' => { skip => "^t::lib" } ]
      : ()
    ),
    [ MetaNoIndex => {
        directory => [qw/t xt examples corpus/],
        'package' => [qw/DB/]
      }
    ],
    ['MetaProvides::Package' => { meta_noindex => 1 } ], # AFTER MetaNoIndex
    [ AutoMetaResources => {
        'repository.github' => 'user:dagolden',
        'bugtracker.rt'     => 1,
        'homepage'          => 'https://metacpan.org/release/%{dist}',
      }
    ],

    'MetaYAML',           # core
    'MetaJSON',           # core

  # build system
    'ExecDir',            # core
    'ShareDir',           # core
    'MakeMaker',          # core

  # copy files from build back to root for inclusion in VCS
  [ CopyFilesFromBuild => {
      copy => 'META.json',
    }
  ],

  # manifest -- must come after all generated files
    'Manifest',           # core

  # before release
    [ 'Git::Check' =>
      {
        allow_dirty => [qw/dist.ini Changes README.pod META.json/]
      }
    ],
    'CheckMetaResources',
    'CheckPrereqsIndexed',
    'CheckChangesHasContent',
    'CheckExtraTests',
    'TestRelease',        # core
    'ConfirmRelease',     # core

  # release
    ( $self->fake_release ? 'FakeRelease' : 'UploadToCPAN'),       # core

  # after release
  # Note -- NextRelease is here to get the ordering right with
  # git actions.  It is *also* a file munger that acts earlier

    # commit dirty Changes, dist.ini, README.pod, META.json
    [ 'Git::Commit' => 'Commit_Dirty_Files' =>
      {
        allow_dirty => [qw/dist.ini Changes README.pod META.json/]
      }
    ],
    [ 'Git::Tag' => { tag_format => $self->tag_format } ],

    # bumps Changes
    'NextRelease',        # core (also munges files)

    [ 'Git::Commit' => 'Commit_Changes' => { commit_msg => "bump Changes" } ],

    [ 'Git::Push' => { push_to => \@push_to } ],

  );

}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: Dist::Zilla configuration the way DAGOLDEN does it
# COPYRIGHT

__END__


=for stopwords
autoprereq dagolden fakerelease pluginbundle podweaver
taskweaver uploadtocpan dist ini

=for Pod::Coverage configure mvp_multivalue_args

=begin wikidoc

= SYNOPSIS

  # in dist.ini
  [@DAGOLDEN]

= DESCRIPTION

This is a [Dist::Zilla] PluginBundle.  It is roughly equivalent to the
following dist.ini:

  ; version provider
  [Git::NextVersion]  ; get version from last release tag
  version_regexp = ^release-(.+)$

  ; choose files to include
  [Git::GatherDir]         ; everything from git ls-files
  exclude_filename = README.pod   ; skip this generated file
  exclude_filename = META.json    ; skip this generated file

  [PruneCruft]        ; default stuff to skip
  [ManifestSkip]      ; if -f MANIFEST.SKIP, skip those, too

  ; file modifications
  [OurPkgVersion]     ; add $VERSION = ... to all files
  [InsertCopyright    ; add copyright at "# COPYRIGHT"
  [PodWeaver]         ; generate Pod
  config_plugin = @DAGOLDEN ; my own plugin allows Pod::WikiDoc

  ; generated files
  [License]           ; boilerplate license
  [ReadmeFromPod]     ; from Pod (runs after PodWeaver)
  [ReadmeAnyFromPod]  ; create README.pod in repo directory
  type = pod
  filename = README.pod
  location = root

  ; t tests
  [Test::Compile]     ; make sure .pm files all compile
  fake_home = 1       ; fakes $ENV{HOME} just in case

  ; xt tests
  [Test::PodSpelling] ; xt/author/pod-spell.t
  [Test::Perl::Critic]; xt/author/critic.t
  [MetaTests]         ; xt/release/meta-yaml.t
  [PodSyntaxTests]    ; xt/release/pod-syntax.t
  [PodCoverageTests]  ; xt/release/pod-coverage.t
  [Test::Portability] ; xt/release/portability.t (of file name)
  options = test_one_dot = 0
  [Test::Version]     ; xt/release/test-version.t

  ; metadata
  [AutoPrereqs]       ; find prereqs from code
  skip = ^t::lib

  [MinimumPerl]       ; determine minimum perl version

  [MetaNoIndex]       ; sets 'no_index' in META
  directory = t
  directory = xt
  directory = examples
  directory = corpus
  package = DB        ; just in case

  [AutoMetaResources] ; set META resources
  bugtracker.rt      = 1
  repository.github  = user:dagolden
  homepage           = https://metacpan.org/release/%{dist}

  [MetaProvides::Package] ; add 'provides' to META files
  meta_noindex = 1        ; respect prior no_index directives

  [MetaYAML]          ; generate META.yml (v1.4)
  [MetaJSON]          ; generate META.json (v2)

  ; build system
  [ExecDir]           ; include 'bin/*' as executables
  [ShareDir]          ; include 'share/' for File::ShareDir
  [MakeMaker]         ; create Makefile.PL

  ; manifest (after all generated files)
  [Manifest]          ; create MANIFEST

  ; copy META.json back to repo dis
  [CopyFilesFromBuild]
  copy = META.json

  ; before release
  [Git::Check]        ; ensure all files checked in
  allow_dirty = dist.ini
  allow_dirty = Changes
  allow_dirty = README.pod
  allow_dirty = META.json

  [CheckMetaResources]     ; ensure META has 'resources' data
  [CheckPrereqsIndexed]    ; ensure prereqs are on CPAN
  [CheckChangesHasContent] ; ensure Changes has been updated
  [CheckExtraTests]   ; ensure xt/ tests pass
  [TestRelease]       ; ensure t/ tests pass
  [ConfirmRelease]    ; prompt before uploading

  ; releaser
  [UploadToCPAN]      ; uploads to CPAN

  ; after release
  [Git::Commit / Commit_Dirty_Files] ; commit Changes (as released)

  [Git::Tag]          ; tag repo with custom tag
  tag_format = release-%v

  ; NextRelease acts *during* pre-release to write $VERSION and
  ; timestamp to Changes and  *after* release to add a new {{$NEXT}}
  ; section, so to act at the right time after release, it must actually
  ; come after Commit_Dirty_Files but before Commit_Changes in the
  ; dist.ini.  It will still act during pre-release as usual

  [NextRelease]

  [Git::Commit / Commit_Changes] ; commit Changes (for new dev)

  [Git::Push]         ; push repo to remote
  push_to = origin

= USAGE

To use this PluginBundle, just add it to your dist.ini.  You can provide
the following options:

* {is_task} -- this indicates whether TaskWeaver or PodWeaver should be used.
Default is 0.
* {auto_prereq} -- this indicates whether AutoPrereq should be used or not.
Default is 1.
* {tag_format} -- given to {Git::Tag}.  Default is 'release-%v' to be more
robust than just the version number when parsing versions for
{Git::NextVersion}
* {version_regexp} -- given to {Git::NextVersion}.  Default
is '^release-(.+)$'
* {fake_release} -- swaps FakeRelease for UploadToCPAN. Mostly useful for
testing a dist.ini without risking a real release.
* {weaver_config} -- specifies a Pod::Weaver bundle.  Defaults to @DAGOLDEN.
* {stopwords} -- add stopword for Test::PodSpelling (can be repeated)
* {no_critic} -- omit Test::Perl::Critic tests
* {no_spellcheck} -- omit Test::PodSpelling tests
* {no_coverage} -- omit PodCoverage tests
* {no_bugtracker} -- DEPRECATED

This PluginBundle now supports ConfigSlicer, so you can pass in options to the
plugins used like this:

  [@DAGOLDEN]
  ExecDir.dir = scripts ; overrides ExecDir

= COMMON PATTERNS

== use github instead of RT

  [@DAGOLDEN]
  :version = 0.32
  AutoMetaResources.bugtracker.github = user:dagolden
  AutoMetaResources.bugtracker.rt = 0

= SEE ALSO

* [Dist::Zilla]
* [Dist::Zilla::Plugin::PodWeaver]
* [Dist::Zilla::Plugin::TaskWeaver]

=end wikidoc

=cut
