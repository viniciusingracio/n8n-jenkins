---

bigbluebutton_html5: true
bigbluebutton_html5_only: true

certbot_enabled: true
certbot_domain: '{{ inventory_hostname }}'
certbot_webroot_cmd: '{{ certbot_base_cmd }} --webroot -w /var/www/bigbluebutton-default/'
bigbluebutton_ssl_certificate: '{{ certbot_cert_path }}/fullchain.pem'
bigbluebutton_ssl_certificate_key: '{{ certbot_cert_path }}/privkey.pem'

bigbluebutton_stun_server:
  - stun:stun1.mconf.com:3478

bigbluebutton_dev_repo: git@github.com:bigbluebutton/bigbluebutton.git
bigbluebutton_dev_repo_ref: master
biglbuebutton_dev_html5_only: yes

bigbluebutton_webhooks: true
