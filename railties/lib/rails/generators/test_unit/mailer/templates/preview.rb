<% module_namespacing do -%>
# Preview all emails at http://localhost:3000/rails/mailers/<%= file_path %>
class <%= class_name %>MailerPreview < ActionMailer::Preview
<% actions.each do |action| -%>

  # Preview this email at http://localhost:3000/rails/mailers/<%= file_path %>/<%= action %>
  def <%= action %>
    <%= class_name %>Mailer.<%= action %>
  end
<% end -%>

end
<% end -%>
