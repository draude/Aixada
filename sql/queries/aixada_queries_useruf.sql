delimiter |


/*******************************************
 * UF STUFF
 *******************************************/


/**
 * 	retrieves list of active/nonactive ufs
 */
drop procedure if exists get_uf_listing|
create procedure get_uf_listing(in incl_inactive boolean)
begin
	declare wherec varchar(255) default '';
	set wherec = if(incl_inactive=1,"","where active = 1"); 
		
	set @q = concat("select
			*
		from 
			aixada_uf 
		", wherec , "
		order by
			id
		desc");
		
	prepare st from @q;
  	execute st;
  	deallocate prepare st;
end |


/**
 * creates a new uf
 */
drop procedure if exists create_uf|
create procedure create_uf(in the_name varchar(255), in the_mentor_uf int)
begin
   declare last_id int;
   start transaction;
   
   select
      max(id) 
	into 
		last_id 
    from 
    	aixada_uf;

   	insert into 
   		aixada_uf (id, name, active, mentor_uf) 
    values 
    	(last_id + 1, the_name, 1, the_mentor_uf);

   	insert into 
   		aixada_account (account_id, balance) 
   	values (1000 + last_id + 1, 0); 
   
   	commit;
   
   	select 
   		* 
   	from 
   		aixada_uf 
   	where 
   		id = last_id + 1;
end|


/**
 * edit existing uf
 */
drop procedure if exists update_uf|
create procedure update_uf(in the_uf_id int, in the_name varchar(255), in is_active tinyint, in the_mentor_uf int)
begin
	update 
  		aixada_uf
  	set 
  		name = the_name, active = is_active, mentor_uf = the_mentor_uf
  	where 
  		id = the_uf_id;
end|



/*******************************************
 * MEMBER STUFF
 *******************************************/
drop procedure if exists get_member_listing|
create procedure get_member_listing(in incl_inactive boolean)
begin
	
	declare wherec varchar(255) default '';
	set wherec = if(incl_inactive=1,"","and mem.active = 1"); 

	set @q = concat("select
		mem.*,
		uf.id as uf_id,
		uf.name as uf_name, 
		u.email, 
		u.last_successful_login
	from 
		aixada_member mem,
		aixada_uf uf, 
		aixada_user u
	where
		u.member_id = mem.id
		and u.uf_id = uf.id
		",wherec,"
	order by
		uf.id desc");
		
	prepare st from @q;
  	execute st;
  	deallocate prepare st;
	
end|


/**
 * 	retrieves detailed member info either for individual member
 *  or for all members of uf. 
 */
drop procedure if exists get_member_info|
create procedure get_member_info (in the_member_id int, in the_uf_id int)
begin
	
	declare wherec varchar(255) default '';
	set wherec = if(the_uf_id>0, concat("uf.id=", the_uf_id),concat("mem.id=",the_member_id)); 
	
	
	
	set @q = concat("select
			mem.*,
			uf.id as uf_id, 
			uf.name as uf_name, 
			uf.mentor_uf,
			u.id as user_id,
			u.login, 
			u.email,
			u.last_login_attempt,
        	u.last_successful_login,
        	u.language,
			u.gui_theme,
        	get_roles_of_member(mem.id) as roles,
    		get_providers_of_member(mem.id) as providers,
    		get_products_of_member(mem.id) as products
    	from 
    		aixada_member mem, 
    		aixada_user u, 
    		aixada_uf uf
    	where
			",wherec,"
			and mem.uf_id = uf.id	    	
			and u.member_id = mem.id");
	
	prepare st from @q;
  	execute st;
  	deallocate prepare st;
	
end|


/**
 * edit members. new members cannot be created without 
 * existing user. 
 */
drop procedure if exists update_member|
create procedure update_member(in the_member_id int, 
 	 	in the_custom_ref varchar(100),
		in the_name varchar(255), 
		in the_nif varchar(15),
        in the_address varchar(255), 
        in the_city varchar(255), 
        in the_zip varchar(10), 
        in the_phone1 varchar(50), 
        in the_phone2 varchar(50),
        in the_web	varchar(255),
        in the_notes text,
        in the_active boolean, 
        in the_participant boolean,
        in the_adult boolean,
        in the_language char(5),
        in the_gui_theme varchar(50),
        in the_email varchar(100)
)
begin
	
	-- update member info -- 
	update 
  		aixada_member 
  	set
  		custom_member_ref = the_custom_ref,
  		nif = the_nif,
       	name = the_name, 
       	address = the_address, 
       	zip = the_zip, 
       	city = the_city, 
       	phone1 = the_phone1, 
       	phone2 = the_phone2, 
       	web = the_web,
       	notes = the_notes,
       	active = the_active,
       	participant = the_participant,
       	adult = the_adult        
  	where 
  		id = the_member_id;
  		
  		
  	-- update related user fields -- 	
  	update 
  		aixada_user u
  	set
  		u.email = the_email, 
  		u.language = the_language,
  		u.gui_theme = the_gui_theme
  	where 
  		u.member_id = the_member_id; 
  	
end|




drop procedure if exists create_member|
create procedure create_member(
        in the_user_id int, 
        in the_name varchar(255), 
        in the_uf_id int, 
        in the_address varchar(255), 
        in the_zip varchar(10), 
        in the_city varchar(255), 
        in the_phone1 varchar(50), 
        in the_phone2 varchar(50))
begin
  declare the_member_id int;
  start transaction;
  insert into aixada_member (
        uf_id, name, address, zip, city, phone1, phone2
  ) values (
        the_uf_id, the_name, the_address, the_zip, the_city, the_phone1, the_phone2
  );
  select last_insert_id() into the_member_id;
  update aixada_user 
  set member_id = the_member_id
  where id = the_user_id;
  commit;
  select id
  from aixada_member
  where id = the_member_id;
end|







/*******************************************
 * USER STUFF
 *******************************************/


/**
 * creates a new user and member. the member does not need an uf
 * at this point but could be assigned in a second step. 
 */
drop procedure if exists register_user|
create procedure register_user(
        in the_login varchar(50), 
        in the_password varchar(255), 
        in the_name varchar(255),
        in the_language char(5),
        in the_address varchar(255),
        in the_zip varchar(10),
        in the_city varchar(255),
        in the_phone1 varchar(50),
        in the_phone2 varchar(50),
        in the_email varchar(255), 
        in the_web varchar(255),
        in the_notes text
        )
begin
  declare the_user_id int;
  start transaction;
  	
  	select 
  		max(id)+1 
  	into 
  		the_user_id
  	from 
  		aixada_user 
  	where id<1000;
  	
  	
  	if the_user_id=0 or isnull(the_user_id) then set the_user_id=1; end if;
  
  	insert into 
  		aixada_member (id, name, address, zip, city, phone1, phone2, web, notes, uf_id) 
  	values 
  		(the_user_id, the_name, the_address, the_zip, the_city, the_phone1, the_phone2, the_web, the_notes, null);
  
  
  	insert into 
  		aixada_user (id, login, password, email, member_id, language, created_on) 
  	values 
 		(the_user_id, the_login, the_password, the_email, the_user_id, the_language, sysdate());
  	
  	
  	insert into 
  		aixada_user_role (user_id, role) 
  	values 
     ( the_user_id, 'Consumer' ),
     ( the_user_id, 'Checkout');
  
	commit;
end|

















drop procedure if exists member_id_of_user_id|
create procedure member_id_of_user_id(in the_user_id int)
begin
  select m.id 
  from aixada_user u
  left join aixada_member m
  on u.member_id = m.id
  where u.id = the_user_id;
end|





drop procedure if exists check_credentials|
create procedure check_credentials(in the_login varchar(50), in the_password varchar(255))
begin
   update aixada_user 
   set last_login_attempt = sysdate() 
   where login=the_login;

   update aixada_user 
   set last_successful_login = sysdate() 
   where login=the_login and password=the_password;
   
select 
   id, login, uf_id, member_id, provider_id, language 
   from aixada_user 
   where login=the_login and password=the_password;
end|



drop procedure if exists check_password|
create procedure check_password(in the_user_id int, in the_password varchar(255))
begin
   select id
   from aixada_user
   where id = the_user_id and password = the_password;
end|











drop procedure if exists find_user_by_login_or_email|
create procedure find_user_by_login_or_email(in the_login varchar(50), in the_email varchar(255))
begin 
   select -8 as id 
   from aixada_user
   where login = the_login
      or email = the_email;
end|







drop procedure if exists register_special_user|
create procedure register_special_user(
        in the_login varchar(50), 
        in the_password varchar(255),
        in the_language char(5),
        in the_uf_name varchar(255)
        )
begin
  declare the_user_id int default 1;
  start transaction;

  insert into aixada_uf (
     id, name
  ) values (
     the_user_id, the_uf_name
  );

  delete from aixada_member where id=1;

  insert into aixada_member (
     id, name, uf_id
  ) values (
     the_user_id, the_login, the_user_id
  ) on duplicate key update name=the_login;

  insert into aixada_user (
      id, login, password, email, uf_id, member_id, language, created_on
  ) values (
      the_user_id, the_login, the_password, '', the_user_id, the_user_id, the_language, sysdate()
  ) on duplicate key update login=the_login, password=the_password, member_id=the_user_id, language=the_language, created_on=sysdate();

  insert into aixada_user_role (
      user_id, role
  ) values 
     (the_user_id, 'Consumer'),
     (the_user_id, 'Checkout'),
     (the_user_id, 'Hacker Commission');
  commit;
end|

drop procedure if exists update_user_email_language_login|
create procedure update_user_email_language_login(
        in the_user_id int, 
        in the_email varchar(100),
        in the_language char(5),
        in the_login varchar(50))
begin
   update aixada_user
   set 
        email = the_email,
        language = the_language,
        login = the_login
   where id = the_user_id;
end|

drop procedure if exists update_password|
create procedure update_password(in the_user_id int, in new_password varchar(255))
begin
  update aixada_user
  set password = new_password
  where id = the_user_id;
end|

drop procedure if exists remove_user_roles|
create procedure remove_user_roles(in the_user_id int)
begin
  delete from aixada_user_role
  where user_id = the_user_id;
end|

drop procedure if exists add_user_role|
create procedure add_user_role(in the_user_id int, in the_role varchar(100))
begin
  insert into aixada_user_role (
     user_id, role
  ) values (
     the_user_id, the_role
  );
end|

drop procedure if exists update_user|
create procedure update_user(
        in the_id int,
        in the_login varchar(50), 
        in the_password varchar(255), 
        in the_email varchar(100),
        in the_uf_id int,
        in the_member_id int,
        in the_provider_id int,
        in the_language char(5),
        in the_color_scheme tinyint)
begin
  update aixada_user 
  set 
        login = the_login,
        password = if(the_password='', password, the_password),
        email = the_email,
        uf_id = the_uf_id,
        member_id = the_member_id,
        provider_id = the_provider_id,
        language = the_language,
        color_scheme = the_color_scheme
  where id = the_id;
  select id 
  from aixada_user 
  where id = the_id;
end|




drop procedure if exists users_without_ufs|
create procedure users_without_ufs()
begin
  select 
    u.id,
 	u.login
  from aixada_user u
  where u.id between 0 and 999 
    and not exists 
        (select auf.id
         from aixada_uf auf
         left join aixada_user au
         on auf.id = au.uf_id
         where au.id = u.id);
end|

drop procedure if exists users_without_uf|
create procedure users_without_uf()
begin
  select id, login, email, created_on as created
  from aixada_user 
  where id between 1 and 999 and 
        isnull(uf_id);
end|

drop procedure if exists users_without_member|
create procedure users_without_member()
begin
  select id, login, email, created_on as created
  from aixada_user 
  where id between 1 and 999 and 
        isnull(member_id);
end|

drop procedure if exists assign_user_to_uf|
create procedure assign_user_to_uf(in the_user_id int, in the_uf_id int)
begin
  update aixada_user
  set uf_id = the_uf_id 
  where id = the_user_id;

  update aixada_member 
  set uf_id = the_uf_id
  where id = the_user_id;
end|

drop procedure if exists get_users|
create procedure get_users()
begin
  select 
        u.id, concat(" UF ", u.uf_id, " ", m.name) as name
  from aixada_user u
  left join aixada_member m
  on u.member_id = m.id
  left join aixada_uf uf
  on u.uf_id = uf.id
  where 
        m.active = true and
        uf.active=true
  order by u.uf_id; 
end|

drop procedure if exists get_active_roles|
create procedure get_active_roles(in the_user_id int)
begin
  select 
        r.role
  from aixada_user u
  left join aixada_user_role r
  on u.id = r.user_id
  where u.id = the_user_id; 
end|

drop procedure if exists get_active_users_for_role|
create procedure get_active_users_for_role(in the_role varchar(100))
begin
  select r.user_id, concat(m.id, ' UF ', m.uf_id, ' ', m.name) as name
  from aixada_user_role r
  left join aixada_member m
  on r.user_id = m.id
  where r.user_id between 1 and 999
    and r.role = the_role
    and m.active=1
  order by m.uf_id;
end|

drop procedure if exists get_inactive_users_for_role|
create procedure get_inactive_users_for_role(in the_role varchar(100))
begin
  select distinct r1.user_id, concat(m.id, ' UF ', m.uf_id, ' ', m.name) as name
  from aixada_user_role r1 
  left join aixada_member m
  on r1.user_id = m.id
  where user_id between 1 and 999
    and m.active=1
    and user_id not in 
     (select user_id 
      from aixada_user_role r2 
      where role=the_role)
  order by m.uf_id;
end|





/**
 * utility functions to extract roles of member, 
 * providers member is responsible for, 
 * and products responsible for.  
 */
drop function if exists get_roles_of_member|
create function get_roles_of_member(the_member_id int)
returns varchar(255)
reads sql data
begin
  declare roles varchar(255);
  select group_concat(role separator ', ') 
  into roles
  from aixada_user_role
  where user_id = the_member_id;
  return roles;
end|

drop function if exists get_providers_of_member|
create function get_providers_of_member(the_member_id int)
returns varchar(255)
reads sql data
begin
  declare providers varchar(255);
  select group_concat(distinct p.name  separator ', ') 
  into providers
  from aixada_member m
  left join aixada_provider p
  on m.uf_id = p.responsible_uf_id
  where m.id = the_member_id;
  return providers;
end|

drop function if exists get_products_of_member|
create function get_products_of_member(the_member_id int)
returns varchar(255)
reads sql data
begin
  declare products varchar(255);
  select group_concat(distinct p.name  separator ', ') 
  into products
  from aixada_member m
  left join aixada_product p
  on m.uf_id = p.responsible_uf_id
  where m.id = the_member_id;
  return products;
end|





delimiter ;
