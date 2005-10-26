%---------------------------------------------------------------------------%
% Copyright (C) 2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% Main author: Ian MacLarty (maclarty@cs.mu.oz.au).
%
%---------------------------------------------------------------------------%
% 
% gen_merc_wxs generates a windows installer for Mercury.  See the file
% README in this directory for more information.
%

:- module gen_merc_wxs.

:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module list.
:- import_module string.

:- import_module wix.

main(!IO) :-
	io.command_line_arguments(Args, !IO),
	( if Args = [Version, Path, GUIDGenCmd, OutFile] then
		Product = product(
			merc_group,
			merc_comp(Version),
			version_no(0, 0, 0, 0), % This is just to keep the
						% Wix compiler happy.
			merc_comp(Version),
			product_comments,
			Path,
			merc_comp(Version)),

		Installer ^ wix_product_info            = Product,
		Installer ^ wix_language                = english_south_africa, 
		Installer ^ wix_set_env_vars            = 
			[set_env_var("PATH", path, prepend, system)],
		Installer ^ wix_shortcut_func           = doc_shortcuts,
		Installer ^ wix_title                   = title, 
		Installer ^ wix_install_heading         = install_heading, 
		Installer ^ wix_install_descr           = install_descr, 
		Installer ^ wix_next_button             = next,
		Installer ^ wix_back_button             = back, 
		Installer ^ wix_cancel_button           = cancel, 
		Installer ^ wix_install_button          = install, 
		Installer ^ wix_cancel_message          = cancel_message, 
		Installer ^ wix_remove_heading          = remove_heading, 
		Installer ^ wix_remove_confirm          = remove_confirm, 
		Installer ^ wix_remove_button           = remove,
		Installer ^ wix_remove_progress_heading = remove_prog_heading, 
		Installer ^ wix_remove_progress_descr   = remove_prog_descr,
		Installer ^ wix_finish_heading          = finish_heading, 
		Installer ^ wix_finish_message          = finish_message, 
		Installer ^ wix_finish_button           = finish,
		Installer ^ wix_files_in_use_heading    = files_in_use_heading, 
		Installer ^ wix_files_in_use_message    = files_in_use_message,
		Installer ^ wix_ignore_button           = ignore, 
		Installer ^ wix_retry_button            = retry,
		Installer ^ wix_yes_button              = yes, 
		Installer ^ wix_no_button               = no, 
		Installer ^ wix_must_be_admin_msg       = admin_message,
		Installer ^ wix_banner_source           = "images\\banner.bmp", 
		Installer ^ wix_background_source       = "images\\bg.bmp",
		Installer ^ wix_wizard_steps            = [
			welcome_wizard_step(welcome, welcome_message),
			license_wizard_step(license_heading, blank, notice_src)
		],

		generate_installer(Installer, GUIDGenCmd, OutFile, Result,
			!IO),
		(
			Result = ok
		;
			Result = wix_error(Error),
			io.format("Error generating wix source: %s\n", 
				[s(string.string(Error))], !IO)
		)
	else
		io.write_string(merc_installer_usage_message, !IO),
		io.nl(!IO)
	).

:- type language_token
	--->	merc_group
	;	merc_comp(string)
	;	product_comments
	;	path
	;	welcome
	;	welcome_message
	;	title
	;	next
	;	back
	;	cancel
	;	install
	;	license_heading
	;	notice_src
	;	cancel_message
	;	yes
	;	no
	;	install_heading
	;	install_descr
	;	remove_heading
	;	remove_confirm
	;	remove
	;	files_in_use_message
	;	files_in_use_heading
	;	ignore
	;	retry
	;	remove_prog_heading
	;	remove_prog_descr
	;	admin_message
	;	finish_heading
	;	finish_message
	;	finish
	;	html_ref_man
	;	html_lib_ref
	;	html_user_guide
	;	pdf_ref_man
	;	pdf_lib_ref
	;	pdf_user_guide
	;	pdf_tutorial
	;	blank.

	% This function is used to generate shortcuts to the Mercury
	% documentation in the Start/Programs menu.
	%
:- func doc_shortcuts(string, string) = list(shortcut(language_token)).

doc_shortcuts(_, FileName) = Shortcuts :-
	( if FileName = "mercury_ref.html" then
		Shortcuts = [shortcut(programs, html_ref_man)]
	else if FileName = "mercury_user_guide.html" then
		Shortcuts = [shortcut(programs, html_user_guide)]
	else if FileName = "mercury_library.html" then
		Shortcuts = [shortcut(programs, html_lib_ref)]
	else if FileName = "reference_manual.pdf" then
		Shortcuts = [shortcut(programs, pdf_ref_man)]
	else if FileName = "user_guide.pdf" then
		Shortcuts = [shortcut(programs, pdf_user_guide)]
	else if FileName = "library.pdf" then
		Shortcuts = [shortcut(programs, pdf_lib_ref)]
	else if FileName = "book.pdf" then
		Shortcuts = [shortcut(programs, pdf_tutorial)]
	else
		Shortcuts = []
	).

:- instance language_independent_tokens(language_token) where [
	pred(translate/3) is translate_token
].

:- pred translate_token(language_token, language, string).
:- mode translate_token(in, in, out) is semidet.
:- mode translate_token(in, in(english), out) is det.

	% Ralph would object...
	%
:- inst english
	--->	english_united_states
	;       english_united_kingdom
	;       english_australia
	;       english_belize
	;       english_canada
	;       english_caribbean
	;       english_hong_kong_sar
	;       english_india
	;       english_indonesia
	;       english_ireland
	;       english_jamaica
	;       english_malaysia
	;       english_new_zealand
	;       english_philippines
	;       english_singapore
	;       english_south_africa
	;       english_trinidad
	;       english_zimbabwe.

translate_token(Token, Language, Translation) :-
	( Language = english_united_states
	; Language = english_united_kingdom
	; Language = english_australia
	; Language = english_belize
	; Language = english_canada
	; Language = english_caribbean
	; Language = english_hong_kong_sar
	; Language = english_india
	; Language = english_indonesia
	; Language = english_ireland
	; Language = english_jamaica
	; Language = english_malaysia
	; Language = english_new_zealand
	; Language = english_philippines
	; Language = english_singapore
	; Language = english_south_africa
	; Language = english_trinidad
	; Language = english_zimbabwe
	),
	token_to_english(Token, Translation).

:- pred token_to_english(language_token::in, string::out) is det.

token_to_english(blank, "").
token_to_english(merc_group, "The Mercury Group").
token_to_english(merc_comp(Version), "Mercury " ++ Version).
token_to_english(product_comments, "").
token_to_english(path, "\"[INSTALLDIR]bin\"").
token_to_english(welcome, "Welcome.").
token_to_english(welcome_message, 
	"This program will install the Melbourne Mercury distribution " ++
	"to your computer. Click Next to continue.").
token_to_english(title, "Mercury installer").
token_to_english(next, "Next >").
token_to_english(back, "< Back").
token_to_english(cancel, "Cancel").
token_to_english(install, "Install").
token_to_english(license_heading, "Licences").
token_to_english(notice_src, "NOTICE.rtf").
token_to_english(cancel_message, "Are you sure you want to cancel?").
token_to_english(yes, "yes").
token_to_english(no, "no").
token_to_english(install_heading, "Installing Mercury").
token_to_english(install_descr, 
	"Installation may take a few minutes, please be patient.").
token_to_english(remove_heading, "Uninstall").
token_to_english(remove_confirm, "Are you sure you wish to uninstall?").
token_to_english(remove, "Remove").
token_to_english(files_in_use_heading, 
	"Some files that need to be updated are currently in use.").
token_to_english(files_in_use_message, 
	"The following applications are using files that need to be " ++
	"updated by this setup. Close these applications and then click " ++
	"Retry to continue the installation or Cancel to exit it.").
token_to_english(retry, "Retry").
token_to_english(ignore, "Ignore").
token_to_english(remove_prog_heading, "Uninstalling").
token_to_english(remove_prog_descr, 
	"Uninstallation may take a few minutes, please be patient.").
token_to_english(admin_message, 
	"You need to be an administrator to install this software.").
token_to_english(finish_heading, "All done.").
token_to_english(finish_message, 
	"Thank you for installing Mercury. " ++
	"Online documentation is avalible from www.cs.mu.oz.au/mercury. " ++
	"Please email any bug reports to mercury-bugs@cs.mu.oz.au. " ++
	"Click finish to exit the Mercury installer.").
token_to_english(finish, "Finish").
token_to_english(html_ref_man, "Reference Manual (HTML)").
token_to_english(pdf_ref_man, "Reference Manual (PDF)").
token_to_english(html_lib_ref, "Library Reference (HTML)").
token_to_english(pdf_lib_ref, "Library Reference (PDF)").
token_to_english(html_user_guide, "User Guide (HTML)").
token_to_english(pdf_user_guide, "User Guide (PDF)").
token_to_english(pdf_tutorial, "Introductory Tutorial (PDF)").

:- func merc_installer_usage_message = string.

merc_installer_usage_message = 
	"Usage: gen_merc_wxs <version> <path to merc files> " ++ 
	"<guid command> <out file>".
