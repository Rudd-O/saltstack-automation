require ["fileinto", "vnd.dovecot.filter"];

# We must run the spamclassifier filter before we run the user
# scripts, otherwise the spam headers will not be available.
filter "spamclassifier";

{% if not spam.file_spam_after_user_scripts %}
{# Keep this snippet in sync with same-named file in sibling folder. #}
if anyof (
	header :contains ["X-Spam-Flag"] ["yes"],
	header :contains ["X-Bogosity"] ["Spam,"]
) {
  fileinto "SPAM";
}
{% endif %}