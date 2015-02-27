FROM phusion/baseimage
MAINTAINER Jason Martin <jason@greenpx.co.uk>

# Set correct environment variables.
ENV DEBIAN_FRONTEND noninteractive
ENV ASTERISKUSER asterisk
ENV ASTERISK_DB_PW pass123
ENV ASTERISKVER 13
ENV FREEPBXVER 12.0.21

CMD ["/sbin/my_init"]

# Setup services
COPY start-apache2.sh /etc/service/apache2/run
RUN chmod +x /etc/service/apache2/run

COPY start-mysqld.sh /etc/service/mysqld/run
RUN chmod +x /etc/service/mysqld/run

COPY start-asterisk.sh /etc/service/asterisk/run
RUN chmod +x /etc/service/asterisk/run

COPY start-amportal.sh /etc/my_init.d/start-amportal.sh

# Following steps on FreePBX wiki
# http://wiki.freepbx.org/display/HTGS/Installing+FreePBX+12+on+Ubuntu+Server+14.04+LTS

# Install Required Dependencies
RUN sed -i 's/archive.ubuntu.com/mirrors.digitalocean.com/' /etc/apt/sources.list \
	&& apt-get update \
	&& apt-get install -y build-essential linux-headers-`uname -r` openssh-server apache2 mysql-server\
		mysql-client bison flex php5 php5-curl php5-cli php5-mysql php-pear php-db php5-gd curl sox\
		libncurses5-dev libssl-dev libmysqlclient-dev mpg123 libxml2-dev libnewt-dev sqlite3\
		libsqlite3-dev pkg-config automake libtool autoconf subversion unixodbc-dev uuid uuid-dev\
		libasound2-dev libogg-dev libvorbis-dev libcurl4-openssl-dev libical-dev libneon27-dev libsrtp0-dev\
		libspandsp-dev \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

# Install PearDB
RUN pear uninstall db \
	&& pear install db-1.7.14

# Compile and install pjproject
WORKDIR /usr/src
RUN curl -sf -o pjproject.tar.gz -L https://github.com/asterisk/pjproject/archive/master.tar.gz \
	&& mkdir pjproject \
	&& tar -xzf pjproject.tar.gz -C pjproject --strip-components=1 \
	&& rm pjproject.tar.gz \
	&& cd pjproject \
	&& ./configure --enable-shared --disable-sound --disable-resample --disable-video --disable-opencore-amr \ 
	&& make dep \
	&& make \
	&& make install \
	&& rm -r /usr/src/pjproject

# Compile and Install jansson
WORKDIR /usr/src
RUN curl -sf -o jansson.tar.gz -L https://github.com/akheron/jansson/archive/master.tar.gz \
	&& mkdir jansson \
	&& tar -xzf jansson.tar.gz -C jansson --strip-components=1 \
	&& rm jansson.tar.gz \
	&& cd jansson \
	&& autoreconf -i \
	&& ./configure \
	&& make \
	&& make install \
	&& rm -r /usr/src/jansson

WORKDIR /usr/src
RUN curl -sf -o asterisk.tar.gz -L http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-$ASTERISKVER-current.tar.gz \
	&& mkdir asterisk \
	&& tar -xzf /usr/src/asterisk.tar.gz -C /usr/src/asterisk --strip-components=1 \
	&& rm asterisk.tar.gz \
	&& cd asterisk \
	&& ./configure \
	&& contrib/scripts/get_mp3_source.sh \
	&& make menuselect.makeopts \
	&& sed -i "s/BUILD_NATIVE//" menuselect.makeopts \
	&& make \
	&& make install \
	&& make config \
	&& ldconfig

WORKDIR /var/lib/asterisk/sounds
RUN curl -sf http://downloads.asterisk.org/pub/telephony/sounds/asterisk-extra-sounds-en-wav-current.tar.gz \
	&& tar -xzf asterisk-extra-sounds-en-wav-current.tar.gz \
	&& rm -f asterisk-extra-sounds-en-wav-current.tar.gz \
	&& curl -sf http://downloads.asterisk.org/pub/telephony/sounds/asterisk-extra-sounds-en-g722-current.tar.gz \
	&& tar -xzf asterisk-extra-sounds-en-g722-current.tar.gz \
	&& rm -f asterisk-extra-sounds-en-g722-current.tar.gz

RUN useradd -m $ASTERISKUSER \
	&& chown $ASTERISKUSER. /var/run/asterisk \ 
	&& chown -R $ASTERISKUSER. /etc/asterisk \
	&& chown -R $ASTERISKUSER. /var/lib/asterisk \
	&& chown -R $ASTERISKUSER. /var/log/asterisk \
	&& chown -R $ASTERISKUSER. /var/spool/asterisk \
	&& chown -R $ASTERISKUSER. /usr/lib/asterisk \
	&& chown -R $ASTERISKUSER. /var/www/ \
	&& chown -R $ASTERISKUSER. /var/www/* \
	&& rm -rf /var/www/html

RUN sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php5/apache2/php.ini \
	&& cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf_orig \
	&& sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
	&& sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# Configure Asterisk database in MYSQL
RUN /etc/init.d/mysql start \
	&& mysqladmin -u root create asterisk \
	&& mysqladmin -u root create asteriskcdrdb \
	&& mysql -u root -e "GRANT ALL PRIVILEGES ON asterisk.* TO $ASTERISKUSER@localhost IDENTIFIED BY '$ASTERISK_DB_PW';" \
	&& mysql -u root -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO $ASTERISKUSER@localhost IDENTIFIED BY '$ASTERISK_DB_PW';" \
	&& mysql -u root -e "flush privileges;"

WORKDIR /usr/src
RUN curl -sf http://mirror.freepbx.org/freepbx-$FREEPBXVER.tgz \
	&& tar xfz freepbx-$FREEPBXVER.tgz \
	&& rm freepbx-$FREEPBXVER.tgz
	&& cd /usr/src/freepbx \
	&& /etc/init.d/mysql start \
	&& /etc/init.d/apache2 start \
	&& /usr/sbin/asterisk \
	&& ./install_amp --installdb --username=$ASTERISKUSER --password=$ASTERISK_DB_PW \
	&& amportal chown \
	&& amportal a ma download manager \
	&& amportal chown \
	&& amportal a ma install manager \
	&& amportal chown \
	#&& amportal a ma installall \
	#&& amportal chown \
	&& amportal a reload \
	&& amportal a ma refreshsignatures \
	&& amportal chown \
	&& ln -s /var/lib/asterisk/moh /var/lib/asterisk/mohmp3 \
	&& rm -r /usr/src/freepbx
