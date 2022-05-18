{% if spam.file_spam_after_user_scripts -%}
require ["fileinto"];

{# Keep this snippet in sync with same-named file in sibling folder. -#}
if anyof (
	header :contains ["X-Spam-Flag"] ["yes"],
	header :contains ["X-Bogosity"] ["Spam,"]
) {
  fileinto "SPAM";
}
{% endif %}