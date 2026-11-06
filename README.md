Ocserv and Ocserv User Management Pannel

    An automatic script for :
    ""install ocserv in linux servers (ubuntu server tested)""
    ""deploy web app with complete installation (nginx, systemctl services and uwsgi)"" 
    run only install.sh in your server to install ocserv and ocserv user managemnet pannel
    dont forgot this command : chmod 755 install.sh

login user pannel params : 

    # username : admin
    # password : random, printed at the end of install.sh (save it!)
    # to change it later:
    #   cd /var/www/html/ocserv_pannel && venv/bin/python manage.py changepassword admin

secret key:

    # a random Django SECRET_KEY is generated on first start in
    # /var/www/html/ocserv_pannel/.secret_key (or set OCSERV_PANEL_SECRET_KEY)
    # restrict panel hosts with OCSERV_PANEL_ALLOWED_HOSTS=vpn.example.com
    

use google reCAPTCHA for login page:

    # nano /var/www/html/ocserv_pannel/ocserv/settings.py 
    add your key instead of  'None' :
        GOOGLE_CAPTCHA_SITE_KEY = None
        GOOGLE_CAPTCHA_SECRET_KEY = None


to sync db with ocpasswd file in pannel:
    
    # chmod 644 /etc/ocserv/ocpasswd 
   

to deactive expire users add this line to crontab :
    
    # 1 0 * * *  /var/www/html/ocserv_pannel/venv/bin/python3 /var/www/html/ocserv_pannel/./manage.py deactive_account


special thanks to : [Shahab Taee](https://linkedin.com/in/shahab-taee-b5510a170)











    




